### installation steps

1. install nix os
   `$ sh <(curl -L https://nixos.org/nix/install)`

2. install yadm
   `$ nix-shell -p yadm`

3. yadm clone repo
   `$ yadm clone git@github.tesla.com:jgoon/df.git`

4. run make in nix
   `$ cd ~/.config/nix && make`

### todo

- [ ] add rectangle config
```
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float .97
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float .97
```

