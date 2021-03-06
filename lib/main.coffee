{CompositeDisposable} = require 'atom'
settings = require './settings'
Ui = require './ui'
globalSubscriptions = require './global-subscriptions'

{isNarrowEditor, getCurrentWord, getVisibleEditors} = require './utils'

module.exports =
  config: settings.config
  lastFocusedNarrowEditor: null
  providers: []

  activate: ->
    @subscriptions = new CompositeDisposable
    settings.removeDeprecated()

    @subscriptions.add atom.workspace.onDidStopChangingActivePaneItem (item) =>
      @lastFocusedNarrowEditor = item if isNarrowEditor(item)

    @subscriptions.add atom.commands.add 'atom-text-editor',
      # Shared commands
      'narrow:focus': => @getUi()?.toggleFocus()
      'narrow:focus-prompt': => @getUi()?.focusPrompt()
      'narrow:refresh': => @getUi()?.refreshManually(force: true)
      'narrow:close': => @getUi(skipProtected: true)?.destroy()
      'narrow:next-item': => @getUi()?.nextItem()
      'narrow:previous-item': => @getUi()?.previousItem()

      # Providers
      'narrow:fold': => @narrow('fold')

      'narrow:symbols': => @narrow('symbols')
      'narrow:symbols-by-current-word': => @narrow('symbols', query: @getCurrentWord())
      'narrow:project-symbols': => @narrow('project-symbols')
      'narrow:project-symbols-by-current-word': => @narrow('project-symbols', query: @getCurrentWord())

      'narrow:git-diff': => @narrow('git-diff')
      'narrow:git-diff-all': => @narrow('git-diff-all')

      'narrow:bookmarks': => @narrow('bookmarks')
      'narrow:linter': => @narrow('linter')

      'narrow:fold-by-current-word': => @narrow('fold', query: @getCurrentWord())

      'narrow:scan': => @narrow('scan')
      'narrow:scan-by-current-word': => @narrow('scan', query: @getCurrentWord())

      # search family
      'narrow:search': => @narrow('search')
      'narrow:search-by-current-word': => @narrow('search', currentWord: true)

      'narrow:search-current-project': => @narrow('search', currentProject: true)
      'narrow:search-current-project-by-current-word': => @narrow('search', currentProject: true, currentWord: true)

      'narrow:atom-scan': => @narrow('atom-scan')
      'narrow:atom-scan-by-current-word': => @narrow('atom-scan', currentWord: true)

      'narrow:toggle-search-start-by-double-click': -> settings.toggle('Search.startByDoubleClick')

    @subscriptions.add atom.commands.add 'atom-text-editor', 'dblclick', =>
      if settings.get('Search.startByDoubleClick')
        @narrow('search', currentWord: true, pending: true)

  getUi: ({skipProtected}={}) ->
    if ui = Ui.get(@lastFocusedNarrowEditor)
      if skipProtected
        return ui unless ui.protected
      else
        return ui

    visibleEditors = getVisibleEditors()
    invisibleNarrowEditor = null
    narrowEditors = atom.workspace.getTextEditors().filter (editor) -> isNarrowEditor(editor)
    if skipProtected
      narrowEditors = narrowEditors.filter (editor) -> not Ui.get(editor).protected

    for editor in narrowEditors
      if editor in visibleEditors
        return Ui.get(editor)
      else
        invisibleNarrowEditor ?= editor
    Ui.get(invisibleNarrowEditor) if invisibleNarrowEditor?

  # Return currently selected text or word under cursor.
  getCurrentWord: ->
    getCurrentWord(atom.workspace.getActiveTextEditor())

  narrow: (providerName, options) ->
    klass = require("./provider/#{providerName}")
    editor = atom.workspace.getActiveTextEditor()
    new klass(editor, options)

  deactivate: ->
    globalSubscriptions.dispose()
    @subscriptions?.dispose()
    {@subscriptions} = {}

  consumeVim: ({getEditorState, observeVimStates}) ->
    @subscriptions.add observeVimStates (vimState) ->
      if isNarrowEditor(vimState.editor)
        vimState.modeManager.onDidActivateMode ({mode, submode}) ->
          switch mode
            when 'insert'
              Ui.get(vimState.editor)?.setReadOnly(false)
            when 'normal'
              Ui.get(vimState.editor)?.setReadOnly(true)

    confirmSearch = -> # return search text
      editor = atom.workspace.getActiveTextEditor()
      vimState = getEditorState(editor)
      text = vimState.searchInput.editor.getText()
      vimState.searchInput.confirm()
      atom.commands.dispatch(vimState.editorElement, 'vim-mode-plus:clear-highlight-search')
      return text

    @subscriptions.add atom.commands.add 'atom-text-editor.vim-mode-plus-search',
      'vim-mode-plus-user:narrow:scan': =>  @narrow('scan', query: confirmSearch(), fromVmp: true)
      'vim-mode-plus-user:narrow:search': => @narrow('search', search: confirmSearch(), fromVmp: true)
      'vim-mode-plus-user:narrow:atom-scan': => @narrow('atom-scan', search: confirmSearch(), fromVmp: true)
      'vim-mode-plus-user:narrow:search-current-project': =>  @narrow('search', search: confirmSearch(), currentProject: true, fromVmp: true)
