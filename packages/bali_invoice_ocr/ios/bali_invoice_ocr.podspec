Pod::Spec.new do |s|
  s.name             = 'bali_invoice_ocr'
  s.version          = '0.1.0'
  s.summary          = 'Internal BALI STOCK invoice OCR bridge.'
  s.description      = <<-DESC
Native invoice OCR for BALI STOCK using Apple Vision.
                       DESC
  s.homepage         = 'https://github.com/Nik13599/BALI-STOCK'
  s.license          = { :type => 'Private' }
  s.author           = { 'BALI' => 'BALI' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.frameworks = 'Vision', 'UIKit'
end
