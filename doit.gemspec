spec = Gem::Specification.new do |s|
  s.name = "doit"
  s.version = "0.0.1"
  s.authors = ["Graeme Hill"]
  s.email = "graemekh@gmail.com"
  s.homepage = "https://github.com/graeme-hill/doit"
  s.platform = Gem::Platform::RUBY
  s.description = File.open("README.md").read
  s.summary = "Convention based build system for c and c++"
  s.files = ["README.md", "lib/doit.rb"]
  s.require_path = "lib"
  s.test_files = []
  s.extra_rdoc_files = ["README.md"]
  s.has_rdoc = true
end
