require "trollop"
require "set"
require "pathname"
require "fileutils"
require "yaml"

module DoIt

  # set some non-configurable directory names
  OBJ_DIR = "obj"
  SRC_DIR = "src"
  BIN_DIR = "bin"
  LIB_DIR = "lib"
  COMPILER = "clang++"
  BUILD_CONFIG_FILE = "build.yml"
  SRC_EXTENSIONS = ["cpp", "c", "cc", "cxx"]

  # contains info necessary to execute a build
  class BuildInfo
    attr_reader :dir, :modules, :extensions

    def initialize(dir, modules, extensions)
      @dir = dir
      @modules = modules
      @extensions = extensions
    end

    def self.load(path, config)
      doc = YAML.load_file(path)
      BuildInfo.new ".", doc[config]["modules"], SRC_EXTENSIONS
    end

    def modules_source_files
      @modules.map { |m| DoIt.files_in_dir(File.join(self.src_dir, m), @extensions, true) }.flatten
    end

    def source_files
      if @modules.any?
        DoIt.files_in_dir(self.src_dir, @extensions, false) + modules_source_files
      else
        DoIt.files_in_dir(self.src_dir, @extensions, true)
      end
    end

    def src_dir
      File.join(@dir, SRC_DIR)
    end

    def bin_dir
      File.join(@dir, BIN_DIR)
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

    def is_stale?
      if not File.exist? @obj_path
        return true
      else
        return File.mtime(@obj_path) < File.mtime(@path)
      end
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

  def self.files_in_dir(dir, extensions, recursive) 
    all = recursive ? Dir[File.join(dir, "**", "*")] : Dir[File.join(dir, "*")]
    all.find_all { |f| extensions.any? { |ext| f.end_with? ".#{ext}" } }
  end

  def self.compile(compiler, source, dest, verbose)
    ensure_dir_exists(File.dirname(dest))
    cmd = "#{compiler} -Wall -c #{source} -o #{dest}"
    if verbose
      puts cmd
    else
      puts "compiling #{source}"
    end
    Kernel.system(cmd)
  end

  def self.link(linker, obj_files, dest, verbose)
    ensure_dir_exists(File.dirname(dest))
    cmd = "#{linker} -o #{dest} \\\n  #{obj_files.join(" \\\n  ")}"
    if verbose
      puts cmd
    else
      puts "linking #{dest}"
    end
    Kernel.system(cmd)
  end

  def self.get_dependency_graph(compiler, src_files)
    dependencies = {}
    src_files.each do |dependee|
      get_dependencies(compiler, dependee).each do |dependency|
        if not dependencies.has_key? dependee
          dependencies[dependee] = Set.new
        end
        dependencies[dependee] << dependency
      end
    end
    return dependencies
  end

  def self.get_dependencies(compiler, file)
    result = `#{compiler} -MM #{file.path}`.split(/[\s\\]+/)[1..-1]
    return result
  end

  def self.clean(base_dir, verbose)
    obj_dir = File.join(base_dir, OBJ_DIR)
    bin_dir = File.join(base_dir, BIN_DIR)
    puts "rm -rf #{obj_dir}" if verbose
    FileUtils.rm_rf(obj_dir)
    puts "rm -rf #{bin_dir}" if verbose
    FileUtils.rm_rf(bin_dir)
  end

  def self.ensure_dir_exists(dir)
    Dir.mkdir(dir) unless File.exists? dir
  end

  def self.file_last_modified(file_path)
    File.mtime file_path 
  end

  def self.build(config, verbose)
    build_info = BuildInfo.load BUILD_CONFIG_FILE, config
    manifest = SourceManifest.new(build_info)
    deps = get_dependency_graph(COMPILER, manifest.files)
    src_files = manifest.files.find_all { |f| f.is_stale? }
    obj_files = manifest.files.map { |f| f.obj_path }
    src_files.each do |f| 
      compile(COMPILER, f.path, f.obj_path, verbose)
    end
    link(COMPILER, obj_files, File.join(build_info.bin_dir, "out"), verbose)
  end

end
