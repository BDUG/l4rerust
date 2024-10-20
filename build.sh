git clone https://github.com/kernkonzept/ham.git &&
cd ham &&
make &&
cd .. &&
mkdir src &&
cd src/ &&
../ham/ham init -u https://github.com/kernkonzept/manifest.git &&
../ham/ham sync &&
cd .. &&
cp -r src/l4rust/ src/l4/pkg/ &&
make setup &&
make &&
mkdir lib &&
find ../obj/ -type f | grep "\.rlib" | xargs -i cp {} . 


