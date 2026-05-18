flutter build macos --release
nvm use --lts
npm install --global create-dmg
create-dmg "build/macos/Build/Products/Release/Task Reporter.app"