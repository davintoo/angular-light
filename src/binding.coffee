
do ->
    alight.hooks.attribute = ext = []

    ext.push
        code: 'dataPrefix'
        fn: ->
            if @.attrName[0..4] is 'data-'
                @.attrName = @.attrName[5..]
            return

    ext.push
        code: 'colonNameSpace'
        fn: ->
            if @.directive or @.name
                return

            parts = @.attrName.match /^(\w+)[\-\:](.+)$/
            if parts
                @.ns = parts[1]
                name = parts[2]
            else
                @.ns = '$global'
                name = @.attrName

            parts = name.match /^([^\.]+)\.(.*)$/
            if parts
                name = parts[1]
                @.attrArgument = parts[2]

            @.name = name.replace /(-\w)/g, (m) ->
                m.substring(1).toUpperCase()
            return

    ext.push
        code: 'getGlobalDirective'
        fn: ->
            if @.directive
                return

            path = alight.d[@.ns]
            if not path
                @.result = 'noNS'
                @.stop = true
                return

            @.directive = path[@.name]
            if not @.directive
                if @.ns is '$global'
                    @.result = 'noNS'
                else
                    @.result = 'noDirective'
                @.stop = true
            return

    ext.push
        code: 'cloneDirective'
        fn: ->
            r = @.directive
            ns = @.ns
            name = @.name
            dir = {}
            if f$.isFunction r
                dir.init = r
            else if f$.isObject r
                for k, v of r
                    dir[k] = v
            else
                throw 'Wrong directive: ' + ns + '.' + name
            dir.priority = r.priority or (alight.priority[ns] and alight.priority[ns][name]) or 0
            dir.restrict = r.restrict or 'A'

            if dir.restrict.indexOf(@.attrType) < 0
                throw 'Directive has wrong binding (attribute/element): ' + name

            @.directive = dir
            return

    ext.push
        code: 'preprocessor'
        fn: ->
            ns = @.ns
            name = @.name
            directive = @.directive
            directive.$init = (cd, element, value, env) ->

                doProcess = ->
                    l = dscope.procLine
                    for dp, i in l
                        dp.fn.call dscope
                        if dscope.isDeferred
                            dscope.procLine = l[i+1..]
                            break
                    dscope.async = true
                    null

                dscope =
                    element: element
                    value: value
                    cd: cd
                    env: env
                    ns: ns
                    name: name
                    doBinding: false
                    # args: args
                    directive: directive
                    isDeferred: false
                    procLine: alight.hooks.directive
                    makeDeferred: ->
                        dscope.isDeferred = true
                        dscope.doBinding = true         # continue binding
                        dscope.retStopBinding = true    # stop binding for child elements
                        dscope.async = false

                        ->
                            dscope.isDeferred = false
                            if dscope.async
                                doProcess()

                if directive.stopBinding
                    env.stopBinding = true

                doProcess()

                if dscope.retStopBinding
                    return 'stopBinding'
                return
            return


do ->
    ext = alight.hooks.directive

    ext.push
        code: 'init'
        fn: ->
            if @.directive.init
                if alight.debug.directive
                    if @.directive.scope
                        console.warn "#{@.ns}-#{@.name} uses scope and init together, probably you need use link instead of init"
                @.env.changeDetector = @.cd

                result = @.directive.init.call @.env, @.cd.scope, @.element, @.value, @.env
                if result and result.start
                    result.start()
            return

    ext.push
        code: 'templateUrl'
        fn: ->
            ds = @
            if @.directive.templateUrl
                callback = @.makeDeferred()
                f$.ajax
                    cache: true
                    url: @.directive.templateUrl
                    success: (html) ->
                        ds.directive.template = html
                        callback()
                    error: callback
            return

    ext.push
        code: 'template'
        fn: ->
            if @.directive.template
                if @.element.nodeType is 1
                    @.element.innerHTML = @.directive.template
                else if @.element.nodeType is 8
                    el = document.createElement 'p'
                    el.innerHTML = @.directive.template.trim()
                    el = el.firstChild
                    f$.after @.element, el
                    @.element = el
                    @.doBinding = true
            return

    ext.push
        code: 'scope'
        fn: ->
            # scope: false, true, 'root'
            if not @.directive.scope
                return

            parentCD = @.cd

            switch @.directive.scope
                when true
                    childCD = parentCD.new
                        $parent: parentCD.scope
                when 'root'
                    childCD = alight.ChangeDetector
                        $parent: parentCD.scope

                    parentCD.watch '$destroy', ->
                        childCD.destroy()
                else
                    throw 'Wrong scope value: ' + @.directive.scope

            @.env.parentChangeDetector = parentCD
            @.cd = childCD

            @.doBinding = true
            @.retStopBinding = true
            return

    ext.push
        code: 'link'
        fn: ->
            if @.directive.link
                @.env.changeDetector = @.cd
                result = @.directive.link.call @.env, @.cd.scope, @.element, @.value, @.env
                if result and result.start
                    result.start()
            return

    ext.push
        code: 'scopeBinding'
        fn: ->
            if @.doBinding and not @.env.stopBinding
                alight.bind @.cd, @.element,
                    skip_attr: @.env.skippedAttr()
            return


testDirective = do ->
    addAttr = (attrName, args, base) ->
        if args.attr_type is 'A'
            attr = base or {}
            attr.priority = alight.priority.$attribute
            attr.is_attr = true
            attr.name = attrName
            attr.attrName = attrName
            attr.element = args.element
            args.list.push attr
        else if args.attr_type is 'M'
            args.list.push base
        return

    (attrName, args) ->
        if args.skip_attr.indexOf(attrName) >= 0
            return addAttr attrName, args,
                skip: true

        attrSelf =
            attrName: attrName
            attrType: args.attr_type
            element: args.element
            cd: args.cd
            result: null
            # result, stop, ns, name, directive

        for attrHook in alight.hooks.attribute
            attrHook.fn.call attrSelf
            if attrSelf.stop
                break

        if attrSelf.result is 'noNS'
            addAttr attrName, args
            return

        if attrSelf.result is 'noDirective'
            if args.attr_type is 'E'
                args.list.push
                    name: attrName
                    priority: -10
                    attrName: attrName
                    noDirective: true
                return

            addAttr attrName, args,
                noDirective: true
            return

        args.list.push
            name: attrName
            directive: attrSelf.directive
            priority: attrSelf.directive.priority
            attrName: attrName
            attrArgument: attrSelf.attrArgument
        return


sortByPriority = (a, b) ->
    if a.priority == b.priority
        return 0
    if a.priority > b.priority
        return -1
    else
        return 1


attrBinding = (cd, element, value, attrName) ->
    text = value || ''
    if text.indexOf(alight.utils.pars_start_tag) < 0
        return

    cd.watchText text, null,
        element: element
        elementAttr: attrName
    true


bindText = (cd, element, option) ->
    text = element.data
    if text.indexOf(alight.utils.pars_start_tag) < 0
        return
    cd.watchText text, null,
        element: element
    text


bindComment = (cd, element, option) ->
    text = element.nodeValue.trim()
    if text[0..9] isnt 'directive:'
        return
    text = text[10..].trim()
    i = text.indexOf ' '
    if i >= 0
        dirName = text[0..i-1]
        value = text[i+1..]
    else
        dirName = text
        value = ''

    args =
        list: list = []
        element: element
        attr_type: 'M'
        cd: cd
        skip_attr: []

    testDirective dirName, args

    d = list[0]
    if d.noDirective
        throw "Comment directive not found: #{dirName}"

    directive = d.directive

    env = new Env
        element: element
        attrName: d.attrName
        attributes: list

    if alight.debug.directive
        console.log 'bind', d.attrName, value, d
    try
        directive.$init cd, element, value, env
    catch e
        alight.exceptionHandler e, 'Error in directive: ' + d.name,
            value: value
            env: env
            cd: cd
            scope: cd.scope
            element: element
    if env.skipToElement
        return {
            directive: 1
            skipToElement: env.skipToElement
        }

    directive: 1
    skipToElement: null


Env = (option) ->
    for k, v of option
        @[k] = v
    @

Env::takeAttr = (name, skip) ->
    if arguments.length is 1
        skip = true
    for attr in @.attributes
        if attr.attrName isnt name
            continue
        if skip
            attr.skip = true
        value = @.element.getAttribute name
        return value or true

Env::skippedAttr = ->
    for attr in @.attributes
        if not attr.skip
            continue
        attr.attrName

Env::scan = (option) ->
    @.changeDetector.scan option

Env::on = (element, eventname, callback) ->
    @.changeDetector.on element, eventname, callback

Env::watch = (name, callback, option) ->
    @.changeDetector.watch name, callback, option

Env::watchGroup = (keys, callback) ->
    @.changeDetector.watchGroup keys, callback

Env::watchText = (expression, callback, option) ->
    @.changeDetector.watchText expression, callback, option

Env::getValue = (name) ->
    @.changeDetector.getValue name

Env::setValue = (name, value) ->
    @.changeDetector.setValue name, value

Env::eval = (exp) ->
    @.changeDetector.eval exp

###
    env.new(scope, option)
    env.new(scope, true)  - makes locals
    env.new(true)  - makes locals
###
Env::new = (scope, option) ->
    if option is true
        option =
            locals: true
    else if scope is true and not option?
        scope = null
        option =
            locals: true

    @.changeDetector.new scope, option

###
    env.bind(cd, element, option)
    env.bind(cd)
    env.bind(element)
    env.bind(element, cd)
    env.bind(option)
    env.bind(env.new(), option)
###
Env::bind = (_cd, _element, _option) ->
    @.stopBinding = true
    count = 0
    for a in arguments
        if a instanceof ChangeDetector
            cd = a
            count += 1
        if f$.isElement a
            element = a
            count += 1
    option = arguments[count]
    if not option
        option =
            skip: @.skippedAttr()
    if not element
        element = @.element
    if not cd
        cd = @.changeDetector
    alight.bind cd, element, option


bindElement = do ->

    (cd, element, config) ->
        fb =
            attr: []
            dir: []
            children: []
        bindResult =
            directive: 0
            hook: 0
            skipToElement: null
            fb: fb
        config = config || {}
        skipChildren = false
        skip_attr = config.skip_attr
        if config.skip is true
            config.skip_top = true
        else if not skip_attr
            skip_attr = config.skip or []
        if not (skip_attr instanceof Array)
            skip_attr = [skip_attr]

        if !config.skip_top
            args =
                list: list = []
                element: element
                skip_attr: skip_attr
                attr_type: 'E'
                cd: cd

            attrName = element.nodeName.toLowerCase()
            testDirective attrName, args
            if attrName is 'script' or attrName is 'style'  # don't process script and style tags
                skipChildren = true

            args.attr_type = 'A'
            for attr in element.attributes
                testDirective attr.name, args

            if config.attachDirective
                for attrName, attrValue of config.attachDirective
                    testDirective attrName, args

            # sort by priority
            list = list.sort sortByPriority

            for d in list
                if d.skip
                    continue
                if d.noDirective
                    throw "Directive not found: #{d.name}"
                d.skip = true
                if config.attachDirective and config.attachDirective[d.attrName]
                    value = config.attachDirective[d.attrName]
                else
                    value = element.getAttribute d.attrName
                if d.is_attr
                    if attrBinding cd, element, value, d.attrName
                        fb.attr.push
                            attrName: d.attrName
                            value: value

                else
                    directive = d.directive
                    env = new Env
                        element: element
                        attrName: d.attrName
                        attrArgument: d.attrArgument or null
                        attributes: list
                        stopBinding: false
                        elementCanBeRemoved: config.elementCanBeRemoved
                        fbElement: config.fbElement
                    if alight.debug.directive
                        console.log 'bind', d.attrName, value, d

                    try
                        if directive.$init(cd, element, value, env) is 'stopBinding'
                            skipChildren = true
                    catch e
                        alight.exceptionHandler e, 'Error in directive: ' + d.attrName,
                            value: value
                            env: env
                            cd: cd
                            scope: cd.scope
                            element: element

                    if env.fastBinding
                        if f$.isFunction env.fastBinding
                            fastBinding = env.fastBinding
                        else
                            fastBinding = directive.init
                        fb.dir.push
                            fb: fastBinding
                            attrName: d.attrName
                            value: value
                            attrArgument: env.attrArgument
                            fbData: env.fbData
                    else
                        bindResult.directive++

                    if env.stopBinding
                        skipChildren = true
                        break

                    if env.skipToElement
                        bindResult.skipToElement = env.skipToElement

        if !skipChildren
            # text bindings
            skipToElement = null
            childNodes = for childElement in element.childNodes
                childElement
            for childElement, index in childNodes
                if not childElement
                    continue
                if skipToElement
                    if skipToElement is childElement
                        skipToElement = null
                    continue
                if config.fbElement
                    childOption =
                        fbElement: config.fbElement.childNodes[index]
                r = bindNode cd, childElement, childOption
                bindResult.directive += r.directive
                bindResult.hook += r.hook
                skipToElement = r.skipToElement
                if r.fb
                    if r.fb.text or (r.fb.attr && r.fb.attr.length) or (r.fb.dir && r.fb.dir.length) or (r.fb.children && r.fb.children.length)
                        fb.children.push
                            index: index
                            fb: r.fb

        bindResult


bindNode = (cd, element, option) ->
    result =
        directive: 0
        hook: 0
        skipToElement: null
        fb: null
    if alight.hooks.binding.length
        for h in alight.hooks.binding
            result.hook += 1
            r = h.fn cd, element, option
            if r and r.owner  # take control
                return result

    if element.nodeType is 1
        r = bindElement cd, element, option
        result.directive += r.directive
        result.hook += r.hook
        result.skipToElement = r.skipToElement
        result.fb = r.fb
    else if element.nodeType is 3
        text = bindText cd, element, option
        if text
            result.fb =
                text: text
    else if element.nodeType is 8
        r = bindComment cd, element, option
        if r
            result.directive += r.directive
            result.skipToElement = r.skipToElement
    result


alight.nextTick = do ->
    timer = null
    list = []
    exec = ->
        timer = null
        dlist = list.slice()
        list.length = 0
        for it in dlist
            callback = it[0]
            self = it[1]
            try
                callback.call self
            catch e
                alight.exceptionHandler e, '$nextTick, error in function',
                    fn: callback
                    self: self
        null

    (callback) ->
        list.push [callback, @]
        if timer
            return
        timer = setTimeout exec, 0


alight.bind = (changeDetector, element, option) ->
    if not changeDetector
        throw 'No changeDetector'

    if not element
        throw 'No element'

    option = option or {}

    if alight.option.domOptimization and not option.noDomOptimization
        alight.utils.optmizeElement element

    root = changeDetector.root

    finishBinding = not root.finishBinding_lock
    if finishBinding
        root.finishBinding_lock = true
        root.bindingResult =
            directive: 0
            hook: 0

    result = bindNode changeDetector, element, option

    root.bindingResult.directive += result.directive
    root.bindingResult.hook += result.hook

    changeDetector.digest()
    if finishBinding
        root.finishBinding_lock = false
        lst = root.watchers.finishBinding.slice()
        root.watchers.finishBinding.length = 0
        for cb in lst
            cb()
        result.total = root.bindingResult

    result
