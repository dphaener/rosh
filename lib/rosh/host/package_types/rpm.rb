require_relative 'base'


class Rosh
  class Host
    module PackageTypes
      class Rpm < Base

        # @param [String] name Name of the packages.
        # @param [Rosh::Host::Shells::Local,Rosh::Host::Shells::Remote] shell
        #   Shell for the OS that's being managed.
        # @param [String] version
        # @param [Status] status
        def initialize(name, shell, version: nil, status: nil)
          super(name, shell, version: version, status: status)
        end

        # Result of `yum info ` as a Hash.
        #
        # @return [Hash]
        def info
          output = @shell.exec "yum info #{@name}"
          info_hash = {}

          output.each_line do |line|
            %r[^(?<key>.*)\s*: (?<value>[^\n]*)\n$] =~ line

            if key && !key.strip.empty?
              info_hash[key.strip.to_safe_down_sym] = value.strip
            elsif value
              last_key = info_hash.keys.last
              info_hash[last_key] << " #{value.strip}"
            end
          end

          info_hash
        end

        # @return [Boolean] +true+ if installed; +false+ if not.
        def installed?
          @shell.exec "yum info #{@name}"

          @shell.last_exit_status.zero?
        end

        # Installs the package using yum and notifies observers with the new
        # version.
        #
        # @param [String] version Version of the package to install.
        # @return [Boolean] +true+ if install was successful, +false+ if not.
        def install(version: nil)
          already_installed = installed?

          cmd = "yum install -y #{@name}"
          cmd << "-#{version}" if version

          @shell.exec(cmd)

          success = @shell.last_exit_status.zero?

          if success && !already_installed
            changed
            notify_observers(self, attribute: :version, old: nil,
              new: info[:version])
          end

          success
        end

        # Removes the package using yum and notifies observers.
        #
        # @return [Boolean] +true+ if install was successful, +false+ if not.
        def remove
          already_installed = installed?
          old_version = info[:version] if already_installed

          @shell.exec "yum remove -y #{@name}"
          success = @shell.last_exit_status.zero?

          if success && already_installed
            changed
            notify_observers(self, attribute: :version, old: old_version,
              new: nil)
          end

          success
        end

        # Upgrades the package, using `yum upgrade`.
        #
        # @return [Boolean] +true+ if install was successful, +false+ if not.
        def upgrade
          already_installed = installed?
          old_version = info[:version] if already_installed

          output = @shell.exec "yum upgrade -y #{@name}"
          success = @shell.last_exit_status.zero?

          return false if output.match(/#{@name} available, but not installed/m)
          return false if output.match(/No Packages marked for Update/m)

          if success && already_installed
            new_version = info[:version]
            changed
            notify_observers(self, attribute: :version, old: old_version,
              new: new_version)
          end

          success
        end
      end
    end
  end
end