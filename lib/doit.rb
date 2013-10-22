require "trollop"
require "set"
require "pathname"
require "fileutils"
require "yaml"

module DoIt

  # set some non-configurable directory names
  OBJ_DIR = "obj"
  SRC_DIR = "src"
  PUBLISH_DIR = "pub"
  LIB_DIR = "lib"
  INCLUDE_DIR = "include"
  BUILD_CONFIG_FILE = "build.yml"
  DEFAULT_SRC_EXTENSIONS = ["cpp", "c", "cc", "cxx"]
  DEFAULT_COMPILER = "clang++"
  DEFAULT_OUTPUT_TYPE = "exe"
  DEFAULT_OUTPUT_NAME = "out"

  # contains info necessary to execute a build
  class BuildInfo
    attr_reader :target, :dir, :modules, :type, :name, :extensions, :external_frameworks, :external_libs, :lflags, :cflags, :compiler

    def initialize(target, dir, modules, type, name, extensions, external_frameworks, external_libs, lflags, cflags, compiler)
      @target = target
      @dir = dir
      @modules = modules
      @type = type
      @name = name
      @extensions = extensions
      @external_frameworks = external_frameworks
      @external_libs = external_libs
      @lflags = lflags
      @cflags = cflags
      @compiler = compiler
    end

    def self.load(path, config)
      DoIt.fatal("#{path} not found") if not File.exists? path
      doc = nil
      begin
        doc = YAML.load_file(path)
      rescue StandardError => e
        DoIt.fatal("Could not read #{path} due this error: #{e}")
      end
      DoIt.fatal("Key #{config} not found in #{path}") if not doc.has_key?(config)
      modules = doc[config].has_key?("modules") ? doc[config]["modules"] : []
      type = doc[config].has_key?("type") ? doc[config]["type"] : DEFAULT_OUTPUT_TYPE
      name = doc[config].has_key?("name") ? doc[config]["name"] : DEFAULT_OUTPUT_NAME
      extensions = doc[config].has_key?("extensions") ? doc[config]["extensions"] : DEFAULT_SRC_EXTENSIONS
      external_frameworks = doc[config].has_key?("external_frameworks") ? doc[config]["external_frameworks"] : []
      external_libs = doc[config].has_key?("external_libs") ? doc[config]["external_libs"] : []
      lflags = doc[config].has_key?("lflags") ? doc[config]["lflags"] : ""
      cflags = doc[config].has_key?("cflags") ? doc[config]["cflags"] : ""
      compiler = doc[config].has_key?("compiler") ? doc[config]["compiler"] : DEFAULT_COMPILER
      BuildInfo.new config, ".", modules, type, name, extensions, external_frameworks, external_libs, lflags, cflags, compiler
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

    def pub_dir
      File.join(@dir, PUBLISH_DIR, target)
    end

    def obj_dir
      File.join(@dir, OBJ_DIR, target)
    end

    def lib_dir
      File.join(@dir, LIB_DIR)
    end

    def include_dir
      File.join(@dir, INCLUDE_DIR)
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
      @obj_path = build_info.obj_dir
      @files = build_info.source_files.map { |s| SourceFileInfo.new(s, @obj_path, build_info.dir) }
    end
  end

  def self.files_in_dir(dir, extensions, recursive) 
    all = recursive ? Dir[File.join(dir, "**", "*")] : Dir[File.join(dir, "*")]
    all.find_all { |f| extensions.any? { |ext| f.end_with? ".#{ext}" } }
  end

  def self.compile(compiler, source, dest, verbose, build_info)

    # extra compiler flags
    cflags = build_info.cflags.empty? ? "" : " #{build_info.cflags}"

    ensure_dir_exists(File.dirname(dest))
    cmd = "#{compiler} -Wall#{cflags} -c #{source} -o #{dest} -I#{build_info.include_dir}"
    if verbose
      puts cmd
    else
      puts "compiling #{source}"
    end

    fatal("compiler failed") unless Kernel.system(cmd)
  end

  def self.link(linker, obj_files, libs, verbose, build_info, pub_info)
    dest = File.join pub_info[:bin_dir], build_info.name

    # include libs and their directories
    lib_dir_string = libs[:lib_dirs].map { |l| " \\\n  -L#{l}" }.join
    lib_string = libs[:libs].map { |l| " \\\n  -l#{l}" }.join

    # include frameworks and their directories
    framework_dir_string = libs[:framework_dirs].map { |f| " \\\n  -F#{f}" }.join
    framework_string = libs[:frameworks].map { |f| " \\\n  -framework #{f}" }.join

    # set load path for frameworks within a mac app bundle
    xlinker = build_info.type == "mac_app_bundle" ? " \\\n  -Xlinker -rpath -Xlinker \"@loader_path/../Frameworks\"" : ""

    # extra linker flags
    lflags = build_info.lflags.empty? ? "" : " \\\n  #{build_info.lflags}"

    # list of obj files
    obj_files = " \\\n  #{obj_files.join(" \\\n  ")}"

    # create the actual linker command and format it nicely so that it's readable in verbose mode
    cmd = "#{linker} -o #{dest}#{lflags}#{xlinker}"
    cmd += lib_dir_string
    cmd += framework_dir_string
    cmd += lib_string
    cmd += framework_string
    cmd += obj_files

    if verbose
      puts cmd
    else
      puts "linking #{dest}"
    end
    
    fatal("linker failed") unless Kernel.system(cmd)
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
    result = `#{compiler} -MM #{file.path} -I./include`.split(/[\s\\]+/)[1..-1]
    return result
  end

  def self.clean(base_dir, verbose)
    obj_dir = File.join(base_dir, OBJ_DIR)
    bin_dir = File.join(base_dir, PUBLISH_DIR)
    puts "rm -rf #{obj_dir}" if verbose
    FileUtils.rm_rf(obj_dir)
    puts "rm -rf #{bin_dir}" if verbose
    FileUtils.rm_rf(bin_dir)
  end

  def self.ensure_dir_exists(dir)
    FileUtils.mkdir_p(dir) unless File.exists? dir
  end

  def self.file_last_modified(file_path)
    File.mtime file_path 
  end

  def self.get_libs(build_info)
    libs = []
    frameworks = []
    lib_dirs = []
    framework_dirs = []

    # find all the static and dynamic libraries included in the lib directory
    Dir["./lib/*"].find_all { |f| not File.file?(f) }.each do |lib_dir|
      has_libs = false
      has_frameworks = false
      Dir["#{lib_dir}/*"].find_all { |f| File.file?(f) || f.end_with?(".framework") }.each do |lib_path|
        base_name = File.basename(lib_path, ".*")
        if File.basename(lib_path).end_with? ".framework"
          has_frameworks = true
          frameworks << base_name
        elsif base_name.start_with? "lib"
          has_libs = true
          libs << base_name[3..-1]
        end
      end
      framework_dirs << lib_dir if has_frameworks
      lib_dirs << lib_dir if has_libs
    end

    # include external system dependencies referenced from build config
    libs += build_info.external_libs
    frameworks += build_info.external_frameworks

    # check for duplicate libs or frameworks
    duplicate_frameworks = frameworks.find_all { |f| frameworks.count(f) > 1 }
    duplicate_libs = libs.find_all { |l| libs.count(l) > 1 }
    fatal("duplicate frameworks found: #{duplicate_frameworks.join(', ')}") if duplicate_frameworks.any?
    fatal("duplicate libs found: #{duplicate_libs.join(', ')}") if duplicate_libs.any?

    return { 
      :libs => libs, 
      :frameworks => frameworks, 
      :lib_dirs => lib_dirs, 
      :framework_dirs => framework_dirs 
    }
  end

  def self.build(config, verbose)
    build_info = BuildInfo.load BUILD_CONFIG_FILE, config
    manifest = SourceManifest.new(build_info)
    deps = get_dependency_graph(build_info.compiler, manifest.files)
    src_files = manifest.files.find_all { |f| f.is_stale? }
    obj_files = manifest.files.map { |f| f.obj_path }
    src_files.each do |f| 
      compile(build_info.compiler, f.path, f.obj_path, verbose, build_info)
    end
    libs = get_libs(build_info)
    pub_info = prepare_publish(build_info)
    link(build_info.compiler, obj_files, libs, verbose, build_info, pub_info)
    publish(pub_info, build_info)
  end

  def self.publish(pub_info, build_info)
    if pub_info.has_key? :frameworks_dir
      build_info.modules.each do |m|
        Dir[File.join(build_info.lib_dir, m, "*.framework")].each do |source|
          dest = pub_info[:frameworks_dir]
          FileUtils.cp_r(source, dest)
        end
      end
    end
  end

  def self.prepare_publish(build_info)
    pub_dir = File.join PUBLISH_DIR, build_info.target
    ensure_dir_exists(pub_dir)
    result = {}

    # if there is already stuff in this directory then get rid of it
    FileUtils.rm_rf(Dir.glob(File.join(pub_dir, "*")))

    # if this is a mac app bundle then we need to create the directory structure
    if build_info.type == "mac_app_bundle"
      # establish directory structure
      app_dir = File.join pub_dir, "#{build_info.name}.app"
      contents_dir = File.join app_dir, "Contents"
      macos_dir = File.join contents_dir, "MacOS"
      frameworks_dir = File.join contents_dir, "Frameworks"
      result[:bin_dir] = macos_dir
      result[:frameworks_dir] = frameworks_dir

      # create folders
      ensure_dir_exists(app_dir)
      ensure_dir_exists(contents_dir)
      ensure_dir_exists(macos_dir)
      ensure_dir_exists(frameworks_dir)
    else
      bin_dir = pub_dir
      resources_dir = File.join pub_dir, "res"
      result[:bin_dir] = bin_dir
      ensure_dir_exists(bin_dir)
    end

    return result
  end

  def self.fatal(msg)
    puts "Error: #{msg}"
    exit
  end

end
