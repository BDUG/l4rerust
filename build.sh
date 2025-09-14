if [ -d "./ham" ]; then
  echo "..."
else
  git clone https://github.com/kernkonzept/ham.git 
fi
cd ham &&
make &&
cd .. &&
cd src/ &&
../ham/ham init -u https://github.com/kernkonzept/manifest.git &&
../ham/ham sync &&
cd .. &&
make setup &&
make &&
# Build example Rust crates including the network server
make examples &&
mkdir lib &&
cd lib/ &&
find ../obj/ -type f | grep "\.rlib" | xargs -i cp {} . 
