require "trollop"

options = Trollop.options do
  opt :clean, "Delete all build artifacts (next build will run from scratch)"
  opt :run, "Run the program after compiling"
end

class BuildInfo
  attr_reader :dir, :modules, :extensions

  def initialize(dir, modules, extensions)
    @dir = dir
    @modules = modules
    @extensions = extensions
  end

  def modules_source_files
    @modules.each { |m| files_in_dir(File.join(@dir, m), @extensions) }.flatten
  end

  def source_files
    if @modules.any?
      files_in_dir(@dir, @extensions) + modules_source_files
    else
      files_in_dir(@dir, @extensions, recursive: true)
    end
  end
end

def files_in_dir(dir, extensions, recursive = false) 
  all = recursive ? Dir[File.join(dir, "**", "*")] : Dir[File.join(dir, "*")]
  all.find_all { |f| extensions.any? { |ext| f.end_with? ".#{ext}" } }
end

def build(build_info)
  p build_info.source_files
end

build BuildInfo.new("./test/basic", [], ["cpp", "h"])
build BuildInfo.new("./test/complex", ["linux", "common"], ["cpp", "h"])
