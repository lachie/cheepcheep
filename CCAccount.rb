#
#  CCTwitter.rb
#  CheepCheep
#
#  Created by Lachie Cox on 10/04/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'
#OSX::require 'MGTwitterEngine'

class CCAccount < OSX::NSObject
	include OSX
	kvc_accessor :active, :statuses, :update_interval
	
	attr_reader :views
	kvc_array_accessor :views
	
	def self.keyPathsForValuesAffectingValueForKey(key)
    if(key == 'selected_tab')
      NSSet.setWithObject('selected_tab_index')
    else
      super_keyPathsForValuesAffectingValueForKey(key)
    end
  end
	
	def initWithDictionary(account)
		if init
			@username = account['username']
			@active   = account['active']
			
			@update_interval = Integer(account['update_interval'])
			@update_interval = 3 if @update_interval < 3
			
			@views    = NSMutableArray.alloc.init
			
			load_views(account['views'])
			load_keychain

		end
		self
	end
	
	def load_views(views_array)
    views_array ||= [{
                       'title' => 'default'
                     }]
		
		views_array.each do |view|
		  insertObject_inViewsAtIndex(CCTab.alloc.initWithAccount_andDictionary(self,view), @views.size)
	  end
	end
	
	def views_to_array
	  []
  end
  
	def to_hash
	  {
	    'username' => @username,
	    'active' => @active,
	    'views' => views_to_array
	  }
  end
  
  
  def load_keychain
    if @username and !@username.strip.empty?
      @keychain_item = EMKeychainProxy.sharedProxy.genericKeychainItemForService_withUsername("CheepCheep",@username)
    end
  end
  
  # accessors
  def username=(username)
    if @keychain_item
      @username = @keychain_item.username = username
    end
  end
  kvc_accessor :username
  
  def password=(password)
    unless @keychain_item
      @keychain_item = EMKeychainProxy.sharedProxy.addGenericKeychainItemForService_withUsername_password("CheepCheep",@username,password)
      disconnect
    else
      disconnect if password != @keychain_item.password
      @keychain_item.password = password
    end
  end
  kvc_writer :password
  
  def password
    @keychain_item ? @keychain_item.password : nil
  end
	
	# connect to twitter
	# yielding the block returns the password and whether the user wants us to save it
	def connect
		if !@twitter && @active && password
			puts "connecting"
			
			@twitter = OSX::MGTwitterEngine.alloc.initWithDelegate(self)
			@twitter.usesSecureConnection = true
			@twitter.setUsername_password(@username,password)
		end
	end
	
	def disconnect
	  @twitter = nil
  end
	
	# update our statuses from twitter
	def update(timer=nil)
	  connect
	  
		req_id = @twitter.getFollowedTimelineFor_since_startingAtPage(nil,nil,0)
		# req_id = @twitter.getUserTimelineFor_since_count(nil,nil,nil)
		@last_update = Time.now
		
		@timer ||= NSTimer.timerWithTimeInterval_target_selector_userInfo_repeats((@update_interval * 60.0), self, 'update:', nil, true)
	end
	
	def sendTweet(tweet)
	  unless tweet.strip.empty?
  	  @twitter.sendUpdate(tweet)
  	end
  end
	
	# MGTwitterEngine delegate machinery
	def requestSucceeded(requestIdentifier)
		puts "requestSucceeded"
	end
	
	def requestFailed_withError(requestIdentifier,error)
		puts "fail"
		p error
		p error.description
	end

  # we got our statuses
  # everyone else discovers this fact via bindings
	def statusesReceived_forRequest(statuses,identifier)
		puts "statusesReceived_forRequest"
		self.statuses = statuses
	end
	
	def directMessagesReceived_forRequest(messages, identifier)
		puts "directMessagesReceived_forRequest"
		p messages
	end
	
	def userInfoReceived_forRequest(userInfo, identifier)
		puts "userInfoReceived_forRequest"
		p userInfo
	end
	
	def imageReceived_forRequest(image,req)
		puts "image: #{image}"
	end
	

	
	# views
	def add_view(plugin,predicate)
	  puts "adding view... at #{@views.size}"
	  cc_tab = CCTab.alloc.initWithAccount_andPredicate_andPlugin(self,predicate,plugin)
    p cc_tab
    insertObject_inViewsAtIndex(cc_tab,@views.size)
    cc_tab
  end
  
  def remove_view(tab)
    index = views.index(tab) or return
    removeObjectFromViewsAtIndex(index)
    index
  end
end
