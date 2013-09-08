#!/usr/bin/ruby

require 'rubygems'

spec = eval File.open("doit.gemspec").read

system %Q{rm *.gem; echo "Y\n" | gem uninstall -a doit; gem build doit.gemspec; gem install doit-#{spec.version}.gem}
