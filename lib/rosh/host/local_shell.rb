require 'pty'
require 'irb'
require 'open-uri'
require 'sys/proctable'
require 'fileutils'
require 'log_switch'
require 'highline/import'
require_relative '../command_result'
require_relative 'local_file_system_object'


class Rosh
  class Host
    class LocalShell
      extend LogSwitch
      include LogSwitch::Mixin

      attr_accessor :last_result
      attr_accessor :last_exit_status
      attr_reader :last_exception
      attr_reader :workspace

      def initialize
        @internal_pwd = Dir.new(Dir.pwd)
        @last_result = nil
        @last_exit_status = 0
        @last_exception = nil
      end

      # @param [String] file Path to the file to cat.
      #
      # @return [String] On success, returns the contents of the file as a String.
      #   On fail, #last_exit_status is set to 1 and returns the Exception that
      #   was raised.
      def cat(file)
        process(file) do |full_file|
          begin
            contents = open(full_file).read
            [contents, 0]
          rescue Errno::ENOENT, Errno::EISDIR => ex
            [ex, 1]
          end
        end
      end

      # @param [String] path The absolute or relative path to make the new working
      #   directory.
      #
      # @return [Dir] On success, returns the new directory.  On fail,
      #   #last_exit_status is set to 1 and returns the Exception that was raised.
      def cd(path)
        process(path) do |full_path|
          begin
            Dir.chdir(full_path)
            @internal_pwd = Dir.new(Dir.pwd)
            [@internal_pwd, 0]
          rescue Errno::ENOENT, Errno::ENOTDIR => ex
            [ex, 1]
          end
        end
      end

      # @param [String] source The path to the file to copy.
      # @param [String] destination The destination to copy the file to.
      #
      # @return [TrueClass] On success, returns +true+.  On fail, #last_exit_status
      #   is set to 1 and returns the Exception that was raised.
      def cp(source, destination)
        process(source, destination) do |full_source, full_destination|
          begin
            ::FileUtils.cp(full_source, full_destination)
            [true, 0]
          rescue Errno::ENOENT, Errno::EISDIR => ex
            [ex, 1]
          end
        end
      end

      # The shell's environment.  Note this doesn't trump the Ruby process's ENV
      # settings (which are still accessible).
      #
      # @return [Hash] A Hash containing the environment info.
      def env
        process do
          @path ||= ENV['PATH'].split(':')

          env = {
            path: @path,
            shell: File.expand_path(File.basename($0), File.dirname($0)),
            pwd: @internal_pwd.to_path
          }

          [env, 0]
        end
      end

      # @param [String] command The system command to execute.
      #
      # @return [String] On success, returns the output of the command.  On
      #   fail, #last_exit_status is whatever was set by the command and returns
      #   the exception that was raised.
      def exec(command)
        process do
          output = ''

          begin
            PTY.spawn(command) do |reader, writer, pid|
              log "Spawned pid: #{pid}"

              begin
                while buf = reader.readpartial(1024)
                  output << buf
                  $stdout.print buf

                  if output.match /Password:$/
                    password = ask('') { |q| q.echo = false }
                    writer.puts password
                  end
                end
              rescue EOFError
                log "Done reading for pid #{pid}"
              end

              Process.wait(pid)
            end

            [output, $?.exitstatus]
          rescue => ex
            [ex, 1]
          end
        end
      end

      # @param [Integer] status Exit status code.
      def exit(status=0)
        Kernel.exit(status)
      end

      # @param [String] path Path to the directory to list its contents.  If no
      #   path given, lists the current working directory.
      #
      # @return [Array<Rosh::LocalFileSystemObject>] On success, returns an
      #   Array of Rosh::LocalFileSystemObjects.  On fail, #last_exit_status is
      #   1 and returns a Errno::ENOENT or Errno::ENOTDIR.
      def ls(path=nil)
        process(path) do |full_path|
          if File.file? full_path
            fso = Rosh::Host::LocalFileSystemObject.create(full_path)
            [fso, 0]
          else
            begin
              fso_array = Dir.entries(full_path).map do |entry|
                Rosh::Host::LocalFileSystemObject.create("#{full_path}/#{entry}")
              end

              [fso_array, 0]
            rescue Errno::ENOENT, Errno::ENOTDIR => ex
              [ex, 1]
            end
          end
        end
      end

      # @param [String] name The name of a command to filter on.
      # @param [Integer] pid The pid of a command to find.
      #
      # @return [Array<Struct::ProcTableStruct>, Struct::ProcTableStruct] When
      #   no options are given, all processes returned.  When +:name+ is given,
      #   an Array of processes that match COMMAND are given.  When +:pid+ is
      #   given, a single process is returned.  See https://github.com/djberg96/sys-proctable
      #   for more info.
      def ps(name: nil, pid: nil)
        process do
          ps = Sys::ProcTable.ps

          if name
            p = ps.find_all { |i| i.cmdline =~ /\b#{name}\b/ }
            [p, 0]
          elsif pid
            p = ps.find { |i| i.pid == pid }
            [p, 0]
          else
            [ps, 0]
          end
        end
      end

      # @return [Dir] The current working directory as a Dir.
      def pwd
        process { [@internal_pwd, 0] }
      end

      # Executes Ruby code in the context of an IRB::WorkSpace.  Thus, variables
      # are maintained across calls to this.
      #
      # @param [String] code The Ruby code to execute.
      #
      # @return [] If the Ruby code raises an exception,
      #   #last_exit_status will be 1 and will return the exception that was
      #   raised.  If no exception was raised, this will return the returned
      #   object from the code that was executed.
      def ruby(code)
        process do
          code.gsub!(/puts/, '$stdout.puts')
          path_info = code.scan(/\s(?<fs_path>\/[^\n]*\/?)$/).flatten

          if $~
            code.gsub!(/#{$~[:fs_path]}/, %["#{path_info.first}"])
          end

          begin
            @workspace ||= IRB::WorkSpace.new(binding)
            r = @workspace.evaluate(binding, code)
            [r, 0]
          rescue Exception => ex
            [ex, 1]
          end
        end
      end

      # @return [Array<String>] List of commands given in the PATH.
      def system_commands
        env[:path].map do |dir|
          Dir["#{dir}/*"].map { |f| ::File.basename(f) }
        end.flatten
      end

      # @return [Integer] Shortcut to the result of the last command executed.
      def _?
        @last_exit_status
      end

      # @return The last exception that was raised.
      def _!
        @last_exception
      end

      private

      # Saves the result of the block given to #last_result and exit code to
      # #last_exit_status.
      #
      # @param [Array<String>, String] paths File paths to expand within the
      #   context of the shell.
      #
      # @return The result of the block that was given
      def process(*paths, &block)
        @last_result, @last_exit_status = if paths.empty?
          block.call
        else
          full_paths = paths.map { |path| preprocess_path(path) }
          block.call(*full_paths)
        end

        @last_exception = @last_result unless @last_exit_status.zero?

        @last_result
      end

      # Expands paths based on the context of the shell.  Allows for using Ruby
      # to pass in a path (via eval).
      #
      # @param [] path A String or some Ruby code that will eval to represent a
      #   path.
      #
      # @return [String] Fully expanded path of the given path.
      def preprocess_path(path)
        path = '' unless path
        path.strip!

        path = unless File.exists? path
          begin
            instance_eval(path)
          rescue NameError, SyntaxError
          end
        end || path

        File.expand_path(path)
      end
    end
  end
end
