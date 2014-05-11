# encoding: utf-8
require 'html/pipeline'
require 'task_list'

class TaskList
  # Returns a `Nokogiri::DocumentFragment` object.
  def self.filter(*args)
    Filter.call(*args)
  end

  # TaskList filter replaces task list item markers (`[ ]` and `[x]`) with
  # checkboxes, marked up with metadata and behavior.
  #
  # This should be run on the HTML generated by the Markdown filter, after the
  # SanitizationFilter.
  #
  # Syntax
  # ------
  #
  # Task list items must be in a list format:
  #
  # ```
  # - [ ] incomplete
  # - [x] complete
  # ```
  #
  # Results
  # -------
  #
  # The following keys are written to the result hash:
  #   :task_list_items - An array of TaskList::Item objects.
  class Filter < HTML::Pipeline::Filter

    Incomplete  = "[ ]".freeze
    Complete    = "[x]".freeze

    # Pattern used to identify all task list items.
    # Useful when you need iterate over all items.
    ItemPattern = /
      ^
      (?:\s*[-+*]|(?:\d+\.))? # optional list prefix
      \s*                     # optional whitespace prefix
      (                       # checkbox
        #{Regexp.escape(Complete)}|
        #{Regexp.escape(Incomplete)}
      )
      (?=\s)                  # followed by whitespace
    /x

    ListSelector = [
      # select UL/OL
      ".//li[starts-with(text(),'[ ]')]/..",
      ".//li[starts-with(text(),'[x]')]/..",
      # and those wrapped in Ps
      ".//li/p[1][starts-with(text(),'[ ]')]/../..",
      ".//li/p[1][starts-with(text(),'[x]')]/../.."
    ].join(' | ').freeze

    # Selects all LIs from a TaskList UL/OL
    ItemSelector = ".//li".freeze

    # Selects first P tag of an LI, if present
    ItemParaSelector = ".//p[1]".freeze

    # List of `TaskList::Item` objects that were recognized in the document.
    # This is available in the result hash as `:task_list_items`.
    #
    # Returns an Array of TaskList::Item objects.
    def task_list_items
      result[:task_list_items] ||= []
    end

    # Renders the item checkbox in a span including the item state.
    #
    # Returns an HTML-safe String.
    def render_item_checkbox(item)
      %(<input type="checkbox"
        class="task-list-item-checkbox"
        #{'checked="checked"' if item.complete?}
        disabled="disabled"
      />)
    end

    # Public: Marks up the task list item checkbox with metadata and behavior.
    #
    # NOTE: produces a string that, when assigned to a Node's `inner_html`,
    # will corrupt the string contents' encodings. Instead, we parse the
    # rendered HTML and explicitly set its encoding so that assignment will
    # not change the encodings.
    #
    # See [this pull](https://github.com/github/github/pull/8505) for details.
    #
    # Returns the marked up task list item Nokogiri::XML::NodeSet object.
    def render_task_list_item(item)
      Nokogiri::HTML.fragment \
        item.source.sub(ItemPattern, render_item_checkbox(item)), 'utf-8'
    end

    # Public: Select all task lists from the `doc`.
    #
    # Returns an Array of Nokogiri::XML::Element objects for ordered and
    # unordered lists.
    def task_lists
      doc.xpath(ListSelector)
    end

    # Public: filters a Nokogiri::XML::Element ordered/unordered list, marking
    # up the list items in order to add behavior and include metadata.
    #
    # Modifies the provided node.
    #
    # Returns nothing.
    def filter_list(node)
      add_css_class(node, 'task-list')

      node.xpath(ItemSelector).reverse.each do |li|
        outer, inner =
          if p = li.xpath(ItemParaSelector)[0]
            [p, p.inner_html]
          else
            [li, li.inner_html]
          end
        if match = (inner.chomp =~ ItemPattern && $1)
          item = TaskList::Item.new(match, inner)
          # prepend because we're iterating in reverse
          task_list_items.unshift item

          add_css_class(li, 'task-list-item')
          outer.inner_html = render_task_list_item(item)
        end
      end
    end

    # Filters the source for task list items.
    #
    # Each item is wrapped in HTML to identify, style, and layer
    # useful behavior on top of.
    #
    # Modifications apply to the parsed document directly.
    #
    # Returns nothing.
    def filter!
      task_lists.each do |node|
        filter_list node
      end
    end

    def call
      filter!
      doc
    end

    # Private: adds a CSS class name to a node, respecting existing class
    # names.
    def add_css_class(node, *new_class_names)
      class_names = (node['class'] || '').split(' ')
      class_names.concat(new_class_names)
      node['class'] = class_names.uniq.join(' ')
    end
  end
end
