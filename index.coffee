# Notebook knows a set of tiles, and has
# a root
_nid = 0
class Notebook
    constructor: ->
        @nodes = []
        @tiles = []
        @root = new NotebookRootNode(@, null)

        @cursoryElement = document.createElement 'div'
        @cursoryElement.className = 'tiled-notebook-cursor'

class NotebookNode
    constructor: (@notebook, @parent) ->
        @notebook.nodes.push @

        @_id = _nid++

        @children = []
        @_handlers = {change: []}

    validate: ->
        @children.forEach (x) -> x.validate()

    update: ->
        @children.forEach (x) -> x.update()

    replaceChild: (a, b) ->
        if b in @children
            throw new Error 'uh oh'

        new_children = []
        for child in @children
            if child is a
                new_children.push b
            else
                new_children.push child
        @children = new_children

    on: (event, fn) ->
        @_handlers[event].push fn

    fire_event: (event, args = []) ->
        for handler in @_handlers[event]
            handler.apply @, args
        if @parent?
            @parent.fire_event event

class NotebookRootNode extends NotebookNode
    constructor: ->
        super

        @element = document.createElement 'div'
        @element.className = 'tiled-notebook-element'

    update: ->
        @fire_event('change')

        # Check to see if we need to update children
        needUpdate = false
        if @element.children.length isnt @children.length
            needUpdate = true
        else
            for child, i in @element.children
                if child isnt @children[i].element
                    needUpdate = true
                    break

        # We do!
        # (this is slow but should happen relatively infrequently)
        if needUpdate
            for child, i in @element.children
                @element.removeChild child
            for child in @children
                @element.appendChild child.element

        @children.forEach (x) -> x.update()

    serialize: -> {type: 'root', children: @children.map((x) -> x.serialize())}

class BinomialNotebookNode extends NotebookNode
    constructor: ->
        super
        @element = document.createElement 'table'
        @element.className = 'tiled-notebook-node'

    # Make sure we still have 2 children, 'cos if not, we should die.
    validate: ->
        @children.forEach (x) -> x.validate()

        # If we are empty, remove us from our parent (disappear)
        if @children.length is 0
            @parent.children = @parent.children.filter (x) => x isnt @

        # If we have only one child, reparent our child to our parent
        if @children.length is 1
            console.log 'Removing', @_id, 'from parent', @parent._id, 'due to single child'
            @parent.replaceChild @, @children[0]
            @children[0].parent = @parent

        if @children.length isnt 2 and @ in @parent.children
            throw new Error 'uh oh'

class VerticalNotebookNode extends BinomialNotebookNode
    constructor: ->
        super

        top_cell = document.createElement 'tr'
        top_cell.appendChild document.createElement 'td'
        @element.appendChild top_cell

        bottom_cell = document.createElement 'tr'
        bottom_cell.appendChild document.createElement 'td'
        @element.appendChild bottom_cell

    # Rerender this node and all its children.
    update: ->
        # Check the DOM against our children
        apparent_children = [
            @element.children[0].children[0].children[0] # <tr><td>
            @element.children[1].children[0].children[0] # <tr><td>
        ]

        if apparent_children[0] isnt @children[0].element
            if apparent_children[0]?
                @element.children[0].children[0].removeChild apparent_children[0]
            @element.children[0].children[0].appendChild @children[0].element
        if apparent_children[1] isnt @children[1].element
            if apparent_children[1]?
                @element.children[1].children[0].removeChild apparent_children[1]
            @element.children[1].children[0].appendChild @children[1].element

        @children.forEach (x) -> x.update()

    serialize: -> {type: 'vertical', children: @children.map((x) -> x.serialize())}

class HorizontalNotebookNode extends BinomialNotebookNode
    constructor: ->
        super

        cell = document.createElement 'tr'
        cell.appendChild document.createElement 'td'
        cell.appendChild document.createElement 'td'
        @element.appendChild cell

    # Rerender this node and all its children.
    update: ->
        # Check the DOM against our children
        apparent_children = [
            @element.children[0].children[0].children[0] # <tr><td>
            @element.children[0].children[1].children[0] # <tr><td>
        ]

        if apparent_children[0] isnt @children[0].element
            if apparent_children[0]?
                @element.children[0].children[0].removeChild apparent_children[0]
            @element.children[0].children[0].appendChild @children[0].element
        if apparent_children[1] isnt @children[1].element
            if apparent_children[1]?
                @element.children[0].children[1].removeChild apparent_children[1]
            @element.children[0].children[1].appendChild @children[1].element

        @children.forEach (x) -> x.update()

    serialize: -> {type: 'horizontal', children: @children.map((x) -> x.serialize())}


_i = 0
class NotebookLeaf extends NotebookNode
    constructor: (@notebook, @parent) ->
        @initializing = true

        @notebook.nodes.push @
        @notebook.tiles.push @

        @children = []
        @_handlers = {change: []}

        @_id = _nid++

        @element = document.createElement 'div'
        @element.className = 'tiled-notebook-leaf-wrapper'

        @borderElement = document.createElement 'div'
        @borderElement.className = 'tiled-notebook-leaf'
        @element.appendChild @borderElement

        @innerElement = document.createElement 'div'
        @innerElement.className = 'tiled-notebook-leaf-editor'
        @borderElement.appendChild @innerElement

        @timeElement = document.createElement 'div'
        @timeElement.className = 'tiled-notebook-timestamp'

        @createdTime = null

        @quill = new Quill @innerElement, {theme: 'bubble', placeholder: 'Write something new...', modules: imageResize: {}}

        # Quill link automatcher. From a Github issue.
        @quill.clipboard.addMatcher Node.TEXT_NODE, (node, delta) ->
            regex = /https?:\/\/[^\s]+/g
            if typeof(node.data) isnt 'string' then return
            matches = node.data.match regex
            if matches? and matches.length > 0
                ops = []
                str = node.data
                for match in matches
                    split = str.split(match)
                    beforeLink = split.shift()
                    ops.push({ insert: beforeLink })
                    ops.push({ insert: match, attributes: { link: match } })
                    str = split.join(match)
                    ops.push({ insert: str })
                delta.ops = ops
            return delta

        @already_created_new = false

        @create_new = =>
            unless @already_created_new
                child = @notebook.root.children[0]
                new_child = new VerticalNotebookNode(@notebook, notebook.root)
                new_tile = new NotebookLeaf(@notebook, new_child)
                new_child.children = [child, new_tile]
                child.parent = new_child
                @notebook.root.replaceChild child, new_child

                @already_created_new = true

                @notebook.root.validate()
                @notebook.root.update()

                # Scroll the new one into view
                bottomTile = notebook.tiles.filter((x) -> not x.already_created_new)[0]
                bottomTile.element.scrollIntoView(false)

        # As soon as the user beings to type in
        @quill.on 'text-change', =>
            unless @initializing
                unless @createdTime?
                    @createdTime = new Date()
                    @update()
                @editedTime = new Date()
                @create_new()
                @fire_event('change')

        @borderElement.addEventListener 'mousedown', (event) =>
            if event.target is @borderElement
                # Display thing
                @notebook.cursoryElement.style.display = 'block'
                @notebook.cursoryElement.style.height = @borderElement.offsetHeight
                @notebook.cursoryElement.style.width = @borderElement.offsetWidth

                {top, left} = @borderElement.getBoundingClientRect()

                @notebook.cursoryElement.style.top = "#{top}px"
                @notebook.cursoryElement.style.left = "#{left}px"

                dy = event.clientY - top
                dx = event.clientX - left

                currentCandidate = null

                mousemoveHandler = (event) =>
                    pos = [x, y] = [event.clientX, event.clientY]

                    best = null
                    min = Infinity
                    for tile in @notebook.tiles when tile isnt @
                        {top, left, right, bottom} = tile.borderElement.getBoundingClientRect()

                        candidates = {
                            top: [(left + right) / 2, top]
                            bot: [(left + right) / 2, bottom]
                            lef: [left, (top + bottom) / 2]
                            rig: [right, (top + bottom) / 2]
                        }

                        for name, candidate of candidates
                            dist = (pos[0] - candidate[0]) ** 2 + (pos[1] - candidate[1]) ** 2
                            if dist < min
                                min = dist
                                best = [tile, name, {top, left, right, bottom}]

                    currentCandidate = [best[0], best[1]]

                    if best?
                        {top, left, right, bottom} = best[2]
                        switch best[1]
                            when 'top'
                                @notebook.cursoryElement.style.top = "#{top}px"
                                @notebook.cursoryElement.style.left = "#{left}px"
                                @notebook.cursoryElement.style.height = "#{(bottom - top) / 2}px"
                                @notebook.cursoryElement.style.width = "#{right - left}px"
                            when 'bot'
                                @notebook.cursoryElement.style.top = "#{(top + bottom) / 2}px"
                                @notebook.cursoryElement.style.left = "#{left}px"
                                @notebook.cursoryElement.style.height = "#{(bottom - top) / 2}px"
                                @notebook.cursoryElement.style.width = "#{right - left}px"
                            when 'lef'
                                @notebook.cursoryElement.style.top = "#{top}px"
                                @notebook.cursoryElement.style.left = "#{left}px"
                                @notebook.cursoryElement.style.height = "#{bottom - top}px"
                                @notebook.cursoryElement.style.width = "#{(right - left) / 2}px"
                            when 'rig'
                                @notebook.cursoryElement.style.top = "#{top}px"
                                @notebook.cursoryElement.style.left = "#{(left + right) / 2}px"
                                @notebook.cursoryElement.style.height = "#{bottom - top}px"
                                @notebook.cursoryElement.style.width = "#{(right - left) / 2}px"

                mouseupHandler = =>
                    # Reparent
                    if currentCandidate?

                        # Remove from current parent
                        [tile, side] = currentCandidate
                        @parent.children = @parent.children.filter (x) => x isnt @

                        # Create other tree
                        if side in ['top', 'bot']
                            new_node = new VerticalNotebookNode(@notebook, tile.parent)

                            if side is 'top'
                                new_node.children = [@, tile]
                            else
                                new_node.children = [tile, @]

                            tile.parent.replaceChild tile, new_node

                            tile.parent = new_node
                            @parent = new_node
                        else
                            new_node = new HorizontalNotebookNode(@notebook, tile.parent)

                            if side is 'lef'
                                new_node.children = [@, tile]
                            else
                                new_node.children = [tile, @]

                            tile.parent.replaceChild tile, new_node

                            tile.parent = new_node
                            @parent = new_node

                        @notebook.root.validate()
                        @notebook.root.update()

                    @notebook.cursoryElement.style.display = 'none'

                    document.body.removeEventListener 'mousemove', mousemoveHandler
                    document.body.removeEventListener 'mouseup', mouseupHandler

                document.body.addEventListener 'mousemove', mousemoveHandler
                document.body.addEventListener 'mouseup', mouseupHandler

    update: ->
        @initializing = false

        super

        if @createdTime?
            if not @createdTimeElement?
                @createdTimeElement = document.createElement 'div'
                @createdTimeElement.className = 'tiled-notebook-create-date'
                @borderElement.appendChild @createdTimeElement

            today = new Date()
            if today.getFullYear() == @createdTime.getFullYear()
                if today.getMonth() == @createdTime.getMonth() and today.getDay() == @createdTime.getDay()
                    @createdTimeElement.innerText = moment(@createdTime).format('H:mm')
                else
                    @createdTimeElement.innerText = moment(@createdTime).format('MMM D')
            else
                @createdTimeElement.innerText = moment(@createdTime).format('MMM YY')

        if @parent isnt @notebook.root and not (
                @parent instanceof VerticalNotebookNode and
                @parent.children[1] is @ and
                @parent.parent is @notebook.root)
            @create_new()

    serialize: -> {type: 'leaf', createdTime: @createdTime?.getTime?(), content: @quill.getContents(), @already_created_new}

deserialize = (serialization, notebook, parent = null) ->
    switch serialization.type
        when 'root'
            node = new NotebookRootNode(notebook, parent)
            node.children = serialization.children.map (x) -> deserialize x, notebook, node
        when 'vertical'
            node = new VerticalNotebookNode(notebook, parent)
            node.children = serialization.children.map (x) -> deserialize x, notebook, node
        when 'horizontal'
            node = new HorizontalNotebookNode(notebook, parent)
            node.children = serialization.children.map (x) -> deserialize x, notebook, node
        when 'leaf'
            node = new NotebookLeaf(notebook, parent)
            if serialization.createdTime?
                node.createdTime = new Date(serialization.createdTime)
            node.already_created_new = serialization.already_created_new
            node.quill.setContents serialization.content
    return node

window.notebook = notebook = new Notebook()

if localStorage.notebook
    notebook.root = deserialize JSON.parse(localStorage.notebook), notebook
else
    first_tile = new NotebookLeaf(notebook, notebook.root)
    notebook.root.children = [first_tile]

notebook.root.on 'change', ->
    localStorage.notebook = JSON.stringify notebook.root.serialize()

notebook.root.validate()
notebook.root.update()

# Find the bottom element
setTimeout (->
    bottomTile = notebook.tiles.filter((x) -> not x.already_created_new)[0]
    bottomTile.element.scrollIntoView(false)
), 0

document.body.appendChild notebook.cursoryElement

document.getElementById('notebook').appendChild notebook.root.element
