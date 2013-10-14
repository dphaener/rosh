require 'observer'
require_relative 'base_methods'
require_relative 'stat_methods'
require_relative '../changeable'
require_relative '../observable'


class Rosh
  class FileSystem

    # A Rosh::FileSystem::File can represent either a file on a local host or a
    # remote host.  It allows you to interact with a file on your file system
    # in an object-oriented manner.
    #
    # Additionally, Files are observable: they can notify other objects when
    # they change.  Observing objects must have an #update method defined that
    # takes parameter list: `(changed_file, attribute: nil, old: nil, new: nil,
    # as_sudo: nil)`.
    #
    #   class MyWatcher
    #     def update(changed_file, attribute: nil, old: nil, new: nil, as_sudo: nil)
    #       puts "File '#{changed_file.path}' changed:"
    #       puts "  attribute:  #{attribute}"
    #       puts "  old value:  #{old}"
    #       puts "  new value:  #{new}"
    #       puts "  using sudo? #{as_sudo}
    #     end
    #   end
    #
    #   watcher = MyWatcher.new
    #   file = Rosh::FileSystem::File.new('/tmp/my_file', 'my_host.com')
    #   file.add_observer(watcher)
    #   file.mode           # => 755
    #   file.chmod(644)
    #   # =>  "File '/tmp/my_file' changed:"
    #   #     "  attribute:  :mode"
    #   #     "  old value:  755"
    #   #     "  new value:  644"
    #   #     "  using sudo? false"
    #
    # The following File attributes can be observed:
    #   * :mode
    #   * :lmode
    #   * :owner
    #   * :lowner
    #   * :exists
    #   * :hard_link
    #   * :symbolic_link
    #   * :name
    #   * :size
    #   * :access_time
    #   * :modification_time
    #
    # Note that notifications/observations are only triggered when made through
    # Rosh--changes external to Rosh are not detected.
    #
    class File
      include BaseMethods
      include StatMethods
      include Rosh::Changeable
      include Rosh::Observable

      def initialize(path, host_name)
        @path = path
        @host_name = host_name
      end

      def create
        change_if(!exists?) do
          notify_about(self, :exists?, from: false, to: true) do
            adapter.create
          end
        end
      end

      def contents
        adapter.read
      end

      def copy_to(destination)
        the_copy = current_host.fs[file: destination]

        criteria = [
          lambda { !the_copy.exists? },
          lambda { the_copy.size != self.size },
          lambda { the_copy.contents != self.contents }
        ]

        change_if(criteria) do
          notify_about(the_copy, :exists?, from: false, to: true) do
            adapter.copy(the_copy)
          end
        end
      end

      def hard_link_from(new_path)
        new_link = current_host.fs[file: new_path]

        criteria = [
          lambda { !new_link.exists? }
        ]

        change_if criteria do
          notify_about(new_link, :exists?, from: false, to: true) do
            adapter.link(new_path)
          end
        end
      end
      alias_method :link, :hard_link_from

      def read(length=nil, offset=nil)
        adapter.read(length, offset)
      end

      def readlines(separator=$/)
        adapter.readlines(separator)
      end

      def each_char(&block)
        adapter.each_char(&block)
      end

      def each_codepoint(&block)
        contents.each_codepoint(&block)
      end

      def each_line(separator=$/, &block)
        contents.each_line(separator, &block)
      end

      # Called by serializer when dumping.
      def encode_with(coder)
        coder['path'] = @path
        coder['host_name'] = @host_name
      end

      # Called by serializer when loading.
      def init_with(coder)
        @path = coder['path']
        @host_name = coder['host_name']
      end

      private

      def adapter
        return @adapter if @adapter

        @adapter = if current_host.local?
          require_relative 'adapters/local_file'
          FileSystem::Adapters::LocalFile
        else
          require_relative 'adapters/remote_file'
          FileSystem::Adapters::RemoteFile
        end

        @adapter.path = @path
        @adapter.host_name = @host_name

        @adapter
      end
    end
  end
end
