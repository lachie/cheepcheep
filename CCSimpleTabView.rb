#
#  CCSimpleTabView.rb
#  CheepCheep
#
#  Created by Lachie Cox on 22/05/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#

require 'osx/cocoa'

class CCSimpleTabView < OSX::NSObject
  def tab_view?; true end
  def bundle; nil end
  def tab_nib; 'StatusList' end
  def name; 'simple' end
end
