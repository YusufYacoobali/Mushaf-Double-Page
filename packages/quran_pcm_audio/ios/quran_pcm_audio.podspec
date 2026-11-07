Pod::Spec.new do |s|
  s.name = 'quran_pcm_audio'
  s.version = '1.0.0'
  s.summary = 'Bounded continuous native PCM output'
  s.description = 'Incremental decoding of local recordings into AVAudioEngine.'
  s.homepage = 'https://github.com/YusufYacoobali/Mushaf-Double-Page'
  s.license = { :type => 'Proprietary' }
  s.author = 'Mushaf'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.frameworks = 'AVFoundation'
end
