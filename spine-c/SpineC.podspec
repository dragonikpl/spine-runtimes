Pod::Spec.new do |s|
	s.name			= 'SpineC'
	s.version      	= '0.1'
	s.license      	=  { :type => 'Copyright 2013 Esoteric Software. All rights reserved.' }
	s.homepage     	= 'http://esotericsoftware.com/'
	s.author      	= 'EsotericSoftware' 
	s.summary      	= '2D skeletal animation runtime for Spine'
	s.source       	= { :git => 'https://github.com/ldomaradzki/spine-runtimes.git', :tag => '0.1' }
	s.source_files 	= 'spine-c/**/*.{h,c}'
	s.platform 		= :ios
	s.ios.deployment_target  = '9.0'
	s.module_name	= 'SpineC'
	s.header_mappings_dir = 'spine-c/include'
	s.public_header_files = 'spine-c/include/spine'
end
