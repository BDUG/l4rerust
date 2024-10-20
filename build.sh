git clone https://github.com/kernkonzept/ham.git &&
cd ham &&
make &&
cd .. &&
cd src/ &&
../ham/ham init -u https://github.com/kernkonzept/manifest.git &&
../ham/ham sync &&
cd .. &&
make setup &&
make &&
mkdir lib &&
cd lib/ &&
find ../obj/ -type f | grep "\.rlib" | xargs -i cp {} . 
