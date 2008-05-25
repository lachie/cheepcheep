#
#  CCAccountWindowController.rb
#  CheepCheep
#
#  Created by Lachie Cox on 10/04/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'
require 'yaml'
require 'fileutils'

class CCAccountWindowController < OSX::NSWindowController
	include OSX
	#kvc_array_accessor :accounts

	kvc_accessor :accounts
	kvc_accessor :selected_account_indexes
	def self.keyPathsForValuesAffectingValueForKey(key)
    if(key == 'selected_account')
      NSSet.setWithObject('selected_account_indexes')
    else
      super_keyPathsForValuesAffectingValueForKey(key)
    end
  end
	
	ib_outlet :accountSheet
	attr_reader :accountSheet
	attr_reader :windowControllers
	
	def accounts_file
	  AppDelegate.app_support_path('accounts.yaml')
  end
	
	def loadAccounts
		filename = accounts_file
		self.accounts = if File.exist?(filename)
			YAML.load_file(filename).inject(NSMutableArray.alloc.init) {|ary,account| ary << CCAccount.alloc.initWithDictionary(account)}
		else
			[].to_ns
		end
	end
	
	def writeAccounts
	  File.write(accounts_file) {|f| f << self.accounts.map {|a| a.to_hash}.to_yaml}
  end
  
  def createWindowsForActiveAccounts
		@windowControllers = self.accounts.collect do |account|
			next unless account.active?
			puts "creat #{account.username}"
			c = CCTwitterController.alloc.initWithAccount(account)
			c.showWindow(self)
			c
		end
	end
  
  
  def selected_account
    puts "selected_account... #{@selected_account_indexes}"
    if @selected_account_indexes and index = @selected_account_indexes.firstIndex and index != NSNotFound
      @accounts[index]
    end
  end
	
	
	def awakeFromNib
	  puts "awake from nib"
	  CCPlugin.load_all_from(AppDelegate.app_support_path("Plugins"))
		loadAccounts
		createWindowsForActiveAccounts
	end
	
	# actions
	ib_action :addAccount do |sender|
		NSApp.beginSheet_modalForWindow_modalDelegate_didEndSelector_contextInfo(accountSheet, self.window, self, 'sheetDidEnd:returnCode:contextInfo:', nil)
	end
	
	ib_action :endAccountSheet do |sender|
		puts "ending sheet #{accountSheet}"
		NSApp.endSheet_returnCode(accountSheet,0)
	end
	

	
	def sheetDidEnd_returnCode_contextInfo(sheet,returnCode,context)
		puts "sheet ended"
		sheet.orderOut(nil)
	end
end
