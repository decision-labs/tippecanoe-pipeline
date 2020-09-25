#!/bin/bash

# set -x

zipped_geodb=$1
output_dir=${2:-output}
data_file_basename=$(basename $zipped_geodb .gdb.zip)
geodatabase="${output_dir}/${data_file_basename}.gdb"

# 1. uncompress geodatabase zip
if [ ! -d $geodatabase ]; then
    unzip -qq $zipped_geodb -d $output_dir
fi

# 2. fetch layers
raw_layers=$(ogrinfo -q $geodatabase)

IFS=$'\n'
count=0
geojson_layers=()

# 3. convert layers to geojson
for raw_layer in $raw_layers; do
    count=$((count + 1))
    if [[ $raw_layer =~ ([[:digit:]]+: )([[:alnum:]_-]+) ]]; then
        echo "layer found: '${BASH_REMATCH[2]}'"
        layer="${BASH_REMATCH[2]}"
    else
        echo "no layer found"
        continue
    fi

    echo "$count: $layer converting to geojson"
    geojson="${output_dir}/${layer}.geojson"
    if [ ! -f "${geojson}" ] ; then
        ogr2ogr -f GeoJSON ${geojson} ${geodatabase} "${layer}" -lco RFC7946=YES
    fi
    echo "created ${geojson}"
    echo "=================================================="
    geojson_layers+=( ${geojson} )
done


# 4. convert geojson to mbtiles
echo "creating mbtiles from ${geojson_layers[@]}"
mbtiles="${data_file_basename}.mbtiles"

if [ ! -f "${output_dir}/${mbtiles}" ] ; then
  tippecanoe \
      -zg \
      -o ${output_dir}/${mbtiles} \
      --drop-densest-as-needed \
      ${geojson_layers[@]}
fi

# ------------------------------
# run mbview
#echo "Do you want to run mbview?(yes/no)"
#read input
#if [ "$input" == "yes" ] ; then
#  echo "running mbview"
#  mbview ${output_dir}/${mbtiles}
#fi
# ------------------------------
