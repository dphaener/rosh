require_relative '../changeable'
require_relative '../observable'


class Rosh
  class Users
    class GroupNotFound < RuntimeError; end

    class Group
      include Rosh::Changeable
      include Rosh::Observable

      attr_reader :group_name

      def initialize(group_name, host_name)
        @group_name = group_name
        @host_name = host_name
      end

      def group_id
        adapter.gid
      end
      alias_method :gid, :group_id

      def members
        adapter.members
      end

      def password
        adapter.passwd
      end

      private

      def adapter
        return @adapter if @adapter

        @adapter = if current_host.local?
          require_relative 'object_adapters/local_group'
          Users::ObjectAdapters::LocalGroup
        else
          case current_host.operating_system
          when :linux
            require_relative 'object_adapters/unix_group'
            Users::ObjectAdapters::UnixGroup
          when :darwin
            require_relative 'object_adapters/open_directory_group'
            Users::ObjectAdapters::OpenDirectoryGroup
          end
        end

        @adapter.group_name = @group_name
        @adapter.host_name = @host_name

        @adapter
      end
    end
  end
end
