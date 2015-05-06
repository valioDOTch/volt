# Require date for require test
require 'date'

module Main
  class MainController < Volt::ModelController
    model :page

    def index
      a = {}
      a[{}] = 5
    end

    def flash_notice
      flash._notices << 'A notice message'
    end

    def flash_success
      flash._successes << 'A success message'
    end

    def flash_warning
      flash._warnings << 'A warning message'
    end

    def flash_error
      flash._errors << 'An error message'
    end

    def cookie_test
      self.model = page._new_cookie!.buffer
    end

    def add_cookie
      cookies.send(:"_#{_name.to_s}=", _value)

      self.model = page._new_cookie!.buffer
    end

    def content_string
      'content'
    end

    def example_html
      '<button id="examplebutton">Example Button</button>'
    end

    private

    # the main template contains a #template binding that shows another
    # template.  This is the path to that template.  It may change based
    # on the params._controller and params._action values.
    def main_path
      "#{params._component || 'main'}/#{params._controller || 'main'}/#{params._action || 'index'}"
    end

    # Determine if the current nav component is the active one by looking
    # at the first part of the url against the href attribute.
    def active_tab?
      url.path.split('/')[1] == attrs.href.split('/')[1]
    end
  end
end
