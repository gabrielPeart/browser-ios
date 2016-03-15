## Anyone with access to the dev@brave.com account can use this to grab the dev and dist profiles

which -s sigh
if [[ $? != 0 ]] ; then
  gem install fastlane --no-doc --no-ri --user-install
fi

rm -rf ~/Library/MobileDevice/Provisioning\ Profiles/*
rm adhoc/*.mobileprovision*

[[ -e ~/.brave-apple-login ]] && source ~/.brave-apple-login

sigh download_all -u dev@brave.com -a com.brave.ios.browser

rm -f *.mobileprovision
