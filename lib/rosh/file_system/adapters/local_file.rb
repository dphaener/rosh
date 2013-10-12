require 'fileutils'
require_relative 'local_base'


class Rosh
  class FileSystem
    module Adapters
      class LocalFile
        include LocalBase

        class << self
          def read(length, offset)
            ::File.read(@path, length, offset)
          end

          def readlines(separator)
            ::File.readlines(@path, separator)
          end

          def copy(destination)
            result = ::FileUtils.cp(@path, destination)

            result.nil?
          end
        end
      end
    end
  end
end
