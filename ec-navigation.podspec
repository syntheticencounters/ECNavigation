require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "ECNavigation"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  ec-navigation
                   DESC
  s.homepage     = "https://github.com/github_account/ec-navigation"
  # brief license entry:
  s.license      = "MIT"
  # optional - use expanded license entry instead:
  # s.license    = { :type => "MIT", :file => "LICENSE" }
  s.authors      = { "Mike Carpenter" => "mike@ecarra.com" }
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/syntheticencounters/ECNavigation" }

  s.source_files = "ios/**/*.{h,c,m,swift}"
  s.requires_arc = true

  s.dependency "React"
  # ...
  # s.dependency "..."
end
