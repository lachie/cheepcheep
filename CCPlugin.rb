#
#  CCPlugin.rb
#  CheepCheep
#
#  Created by Lachie Cox on 21/05/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

module CCPluginSugar
end

class CCPlugin < OSX::NSObject
  
  def self.load_bundles_from(plugins_path,bundles)
    Dir["#{plugins_path}/**/*.bundle"].each do |bundle|
      puts "bundle! #{bundle}"
      b = OSX::NSBundle.bundleWithPath(bundle)
      
      unless b
        puts "[#{bundle}] failed to load"
        next
      end
      
      plugin_class_name = b.objectForInfoDictionaryKey("CCPluginClass")
      
      
      unless plugin_class_name
        puts "[#{bundle}] bundle needs CCPluginClass key"
        next
      end
      
      Dir["#{b.resourcePath.fileSystemRepresentation}/**/*.rb"].each do |file|
        require file
      end
            
      bundles[plugin_class_name.to_s] = b
    end
  end
  
  def self.load_standalones_from(plugins_path)
    Dir["#{plugins_path}/**/*_plugin.rb"].each do |file|
      require file
    end
  end
  
  def self.load_all_from(plugins_path)
	  FileUtils::mkdir_p(plugins_path)
	  
	  bundles = {}

    load_bundles_from(plugins_path,bundles)
    load_standalones_from(plugins_path)
    
    # instantiate and hook up bundles
    registered_plugin_classes.each do |klass|
      c = CCPlugin.plugins[klass.to_s] = klass.alloc.init
      if bundle = bundles[klass.to_s]
        c.bundle = bundle
      end
    end
  end
  
  @plugins = {}
  @registered_plugin_classes = []
  
  def self.inherited(child)
    super
    CCPlugin.registered_plugin_classes << child
  end

  class << self
    attr_reader :plugins, :registered_plugin_classes
  end
  
  def init
    puts "init... plugin"
    super_init
  end

  attr_accessor :bundle
  
  def bundle?
    !!bundle
  end
  
  def name
    raise NotImplementedError
  end
  
  def quacks?(*method_names)
    method_names.all? {|m| self.respond_to? m}
  end
  
  
  # tab views
  def self.tab_views
    @plugins.values.select {|p| p.tab_view?}
  end
  
  def tab_view?
    quacks?(:tab_nib) && bundle?
  end
end