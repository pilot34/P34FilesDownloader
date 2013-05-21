Pod::Spec.new do |s|
  s.name         = 'P34FilesDownloader'
  s.version      = '0.0.1'
  s.summary      = 'Some useful utils classes.'
  s.homepage     = 'https://github.com/pilot34/P34FilesDownloader'
  s.license      = 'MIT'
  s.author       = { 'pilot34' => 'gleb34@gmail.com' }
  s.source       = { :git => 'https://github.com/pilot34/P34FilesDownloader.git' }
  s.platform     = :ios, '5.0'
  s.source_files = 'P34FilesDownloader/*.{h,m}'
  s.requires_arc = true
  
  s.dependency 'P34Utils', :git => 'https://github.com/pilot34/P34Utils.git'
  s.dependency 'ASIHTTPRequest'
end