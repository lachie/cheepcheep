#
#  CCWindowController.rb
#  CheepCheep
#
#  Created by Lachie Cox on 10/04/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

class CCTwitterController < OSX::NSWindowController
  include OSX
  
  kvc_accessor :selected_tab_index
  
  def self.keyPathsForValuesAffectingValueForKey(key)
    if(key == 'selected_tab')
      NSSet.setWithObject('selected_tab_index')
    else
      super_keyPathsForValuesAffectingValueForKey(key)
    end
  end
  
	attr_accessor :account
	
	ib_outlet :tab_view
	ib_outlet :editor
	
	

	def initWithAccount(account)
		if initWithWindowNibName('Twitter')
			@account = account
		end

		self
	end
	
	def windowWillLoad
		puts "windowWillLoad"
	  account.addObserver_forKeyPath_options_context(self, "views", (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionNew), nil)
	end
	
	
	def windowDidLoad
    # puts "windowDidLoad"
    # @original_editor_frame = @editor.frame
    #     pp @original_editor_frame
    #     @editor.setFrame([0,0,0,0])
	  
		self.window.frameAutosaveName = self.account.username	  
	  add_tabs
	end
	
	# tab plugins types
	def tab_plugins
	  CCTab.tab_plugins
  end
	
	# set up a new tab
	# tabs are backed by a CCTab model
	def addTabWithPlugin_andPredicate(plugin,predicate)
    account.add_view(plugin,predicate)
  end
  
  def add_tabs(new_select_tab=nil)
    self.selected_tab_index = nil
    
    @tab_view.tabViewItems.each {|tab| @tab_view.removeTabViewItem(tab)}
    account.views.each {|tab| add_tab(tab)}
    
    index = new_select_tab ? account.views.index(new_select_tab) : 0
    if @tab_view.numberOfTabViewItems > 0
      @tab_view.selectTabViewItemAtIndex(index)
    end
  end
  
  def add_tab(cc_tab)	  
	  # create the NSTabViewItem
	  ns_tab = NSTabViewItem.alloc.initWithIdentifier(nil)
	  ns_tab.view = cc_tab.view
	  
	  # wire up some extra bindings magic
	  ns_tab.bind_toObject_withKeyPath_options("label",cc_tab,"title",nil)
	  
	  # this wires up the tabViewItem's label to the tab's title
	  # its handled below in observeValueForKeyPath_ofObject_change_context
	  cc_tab.addObserver_forKeyPath_options_context(self, "view_controller", (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionNew), nil)

	  @tab_view.addTabViewItem(ns_tab)
  end
  
  def remove_tab(tab)
    tab.removeObserver_forKeyPath(self,"view_controller")
  end
  
  def change_tab_view(tab)
    index = account.views.index(tab)
    @tab_view.tabViewItemAtIndex(index).view = tab.view
  end
  
  def selected_tab
    if @selected_tab_index
      account.views[@selected_tab_index.to_i]
    else
      nil
    end
  end
  
  require 'pp'
  # kvo
  def observeValueForKeyPath_ofObject_change_context(key_path,object,change,ctx)
    puts "observeValueForKeyPath_ofObject_change_context"
    puts key_path
    pp change
    if key_path == 'view_controller' && object.respond_to?(:view)
      change_tab_view(object)
    end
    
    if key_path == 'views'
      if change['new']
        add_tabs(change['new'].first)
      else
        add_tabs
      end
    end
  end
  
	
	# actions
	ib_action(:addTab) do |sender|
	  account.add_view(nil,nil)
  end
  
  ib_action(:removeTab) do |sender|
    last_tab = selected_tab
    self.selected_tab_index = nil
    
    last_index = account.remove_view(last_tab)
  end

  ib_action(:sendTweet) do |sender|
    account.sendTweet(sender.stringValue)
    sender.stringValue = ''
  end
  
  ib_action(:closePasswordWindow) do |sender|
    @password_window.orderOut(self)
    NSApp.stopModal
  end

end