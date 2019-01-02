Pod::Spec.new do |s|
	s.name			= 'SpineSwiftMetal'
	s.version      	= '0.1'
	s.license      	=  { :type => 'Copyright 2013 Esoteric Software. All rights reserved.' }
	s.homepage     	= 'http://esotericsoftware.com/'
	s.author      	= 'EsotericSoftware' 
	s.summary      	= '2D skeletal animation runtime for Spine'
	s.source       	= { :git => 'https://github.com/ldomaradzki/spine-runtimes.git', :tag => '0.1' }
	s.source_files 	= 'spine-swift-metal/*.{h,m,swift}', 'extensions/*.swift'
	#s.resources		= '*.metal'
	s.platform 		= :ios
	s.ios.deployment_target  = '10.0'
	s.dependency 'SpineC'
	
end
