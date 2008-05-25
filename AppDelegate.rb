require 'osx/cocoa'
require 'fileutils'
class AppDelegate < OSX::NSObject
  include OSX

  def self.app_support_path(*extra)
    unless @app_support
      paths = OSX::NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, true)
    
      @app_support = File.join(paths.first.to_s,'CheepCheep')
      
      unless File.directory?(@app_support)
        FileUtils::mkdir_p @app_support
      end
    end
	
	  if extra.empty?
  		@app_support
  	else
  		File.join(@app_support,*extra)
  	end
  end
  
  def applicationDidFinishLaunching(app)
    puts "applicationDidFinishLaunching..."
  end
  
end