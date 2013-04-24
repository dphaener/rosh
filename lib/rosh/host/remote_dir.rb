require_relative 'remote_file_system_object'


class Rosh
  class Host
    class RemoteDir < RemoteFileSystemObject

      # @return [String] The owner of the remote directory.
      def owner
        cmd = "ls -ld #{@path} | awk '{print $3}'"

        @remote_shell.exec(cmd).strip
      end

      # @return [String] The group of the remote directory.
      def group
        cmd = "ls -ld #{@path} | awk '{print $4}'"

        @remote_shell.exec(cmd).strip
      end

      # @return [Integer] The mode of the file system object.
      def mode
        cmd = "ls -ld #{@path} | awk '{print $1}'"
        letter_mode = @remote_shell.exec(cmd)

        mode_to_i(letter_mode)
      end

      # Creates the directory if it doesn't already exist.
      #
      # @return [Boolean] +true+ if the directory already exists or if creating
      #   it was successful; +false+ if creating it failed.
      def save
        return true if exists?

        cmd = "mkdir -p #{@path}"
        @remote_shell.exec(cmd)

        success = @remote_shell.last_exit_status.zero?

        if success
          changed
          notify_observers(self, attribute: :path, old: nil, new: @path)
        end

        success
      end
    end
  end
end
