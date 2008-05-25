#
#  CCTab.rb
#  CheepCheep
#
#  Created by Lachie Cox on 21/05/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

class CCTab < OSX::NSObject
  include OSX
  
	kvc_accessor :account, :title
	
	attr_accessor :tab
	
	def init
	  puts "init"
	  
	  if super_init
    end
    
    self
  end
	
	def initWithAccount_andPredicate_andPlugin(account,predicate,plugin)
	  puts "initWithAccount_andPredicate_andPlugin"
	  
	  if init
  	  self.predicate = predicate
  	  @account       = account
  	  self.plugin    = plugin  
  	end
  	
  	self
  end
  
  def initWithAccount_andDictionary(account,tab)
    puts "CCTab initWithDictionary"
    
    if init
      self.account             = account
      self.predicate_as_string = tab['predicate']
      self.title               = tab['title']
      self.plugin_as_string    = tab['plugin']
    end

    self
  end
  
  # def inspect
  #   "#{super} predicate pred: #{predicate.predicateFormat} ... plugin: #{plugin} ... title: #{title}"
  # end
  
  # plugins
  def self.tab_plugins
    @tab_plugins ||= [CCSimpleTabView.alloc.init, *CCPlugin.tab_views].to_ns
  end
  
  def plugin_as_string=(str)
    self.plugin = if str
                    self.class.tab_plugins.find {|p| p.name == str}
                  else
                    nil
                  end
  end
  
  def plugin=(plugin)
    @plugin = plugin || self.class.tab_plugins.first
    
  	self.view_controller = NSViewController.alloc.initWithNibName_bundle(@plugin.tab_nib,@plugin.bundle)
  end
  kvc_accessor :plugin
  
  
  # predicate
  require 'pp'
  def predicate_as_string=(predicate)
    puts "setting predicate as string to #{predicate.inspect}"
    
    self.predicate = predicate ? NSPredicate.predicateWithFormat(predicate) : nil
  end
  
  # a predicate which matches everything
	def null_predicate
    NSCompoundPredicate.andPredicateWithSubpredicates([])
  end
  
  def predicate
    puts "getting predicate"
    # pp caller
    
    @predicate || null_predicate
  end
  kvc_writer :predicate
  
  def view_controller=(vc)
    @view_controller = vc
    vc.representedObject = self
  	vc.loadView
  end
  kvc_accessor :view_controller
  
  def view
    @view_controller.view
  end
end