require "trollop"
require "pathname"
require "fileutils"

# set some non-configurable directory names
OBJ_DIR = "obj"
SRC_DIR = "src"
BIN_DIR = "bin"
LIB_DIR = "lib"

# configure command line arguments
options = Trollop.options do
  opt :clean, "Delete all build artifacts (next build will run from scratch)"
  opt :run, "Run the program after compiling"
end

# contains info necessary to execute a build
class BuildInfo
  attr_reader :dir, :modules, :extensions

  def initialize(dir, modules, extensions)
    @dir = dir
    @modules = modules
    @extensions = extensions
  end

  def modules_source_files
    @modules.map { |m| files_in_dir(File.join(self.src_dir, m), @extensions, true) }.flatten
  end

  def source_files
    if @modules.any?
      files_in_dir(self.src_dir, @extensions, false) + modules_source_files
    else
      files_in_dir(self.src_dir, @extensions, true)
    end
  end

  def src_dir
    File.join(@dir, SRC_DIR)
  end
end

# metadata for each source file (like obj file destination path)
class SourceFileInfo
  attr_reader :path, :obj_path

  def initialize(path, obj_path, base_path)
    @path = path
    local_path = Pathname.new(path).relative_path_from(Pathname.new(File.join(base_path, SRC_DIR)))    
    dirty_obj_path = File.join(obj_path, File.dirname(local_path), File.basename(local_path, ".*")) + ".o"
    @obj_path = Pathname.new(dirty_obj_path).cleanpath
  end

end

# describes a set of source files to be compiled
class SourceManifest
  attr_reader :files, :obj_path

  def initialize(build_info)
    @obj_path = File.join(build_info.dir, OBJ_DIR)
    @files = build_info.source_files.map { |s| SourceFileInfo.new(s, @obj_path, build_info.dir) }
  end
end

def files_in_dir(dir, extensions, recursive) 
  all = recursive ? Dir[File.join(dir, "**", "*")] : Dir[File.join(dir, "*")]
  all.find_all { |f| extensions.any? { |ext| f.end_with? ".#{ext}" } }
end

def compile(compiler, source, dest)
  ensure_dir_exists(File.dirname(dest))
  cmd = "#{compiler} -Wall -c #{source} -o #{dest}"
  p cmd
  Kernel.system(cmd)
end

def clean(base_dir)
  FileUtils.rm_rf(File.join(base_dir, "OBJ_DIR"))
  FileUtils.rm_rf(File.join(base_dir, "BIN_DIR"))
end

def ensure_dir_exists(dir)
  Dir.mkdir(dir) unless File.exists? dir
end

def build(build_info)
  manifest = SourceManifest.new(build_info)
  manifest.files.each { |f| compile("clang++", f.path, f.obj_path) }
end

clean("./test/basic")
clean("./test/complex")

#build BuildInfo.new("./test/basic", [], ["cpp"])
#p "------------"
#build BuildInfo.new("./test/complex", ["linux", "common"], ["cpp"])
