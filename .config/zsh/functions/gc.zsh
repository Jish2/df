# clone a github.tesla.com repo into ~/github and open it in VS Code
gc() {
  (cd ~/github && git clone "git@github.tesla.com:$1.git" && code "$(basename "$1" .git)")
}
