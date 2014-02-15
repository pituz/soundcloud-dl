#!/usr/bin/env bash
# Author: FlyinGrub
# Check my github : https://github.com/flyingrub/soundcloud-dl
# Share it if you like ;)
##############################################################

echo ''
echo ' *---------------------------------------------------------------------------*'
echo '|      SoundcloudMusicDownloader(cURL/Wget version) |   FlyinGrub rework      |'
echo ' *---------------------------------------------------------------------------*'

download() {
    local verbose cont out opt opts OPTIND
    while getopts "cv" opt; do
	case "$opt" in
	    c) cont=1;;
	    v) verbose=1;;
	esac
    done
    shift $((OPTIND-1))
    [ "$cont" ] && out="$2.part" || out="${2--}"
    if [ "$curlinstalled" ]; then
	[ "$verbose" ] && opts="-#" || opts="-s"
	[ "$cont" ] && [ -f "$out" ] && opts+=" -C -"
        curl $opts -L --user-agent 'Mozilla/5.0' "$1" -o "$out"
    else
	[ "$verbose" ] && verbose="--progress=bar" || verbose="-q"
        wget $verbose --max-redirect=1000 --trust-server-names -U 'Mozilla/5.0' -O "$out" "$1" "${cont+-c}"
    fi
    [ "$?" = 0 ] && [ "$cont" ] && mv "$out" "${out%.part}"
}

function settags() {
    ((writags)) || { 
        echo "[i] Setting tags skipped (please install eyeD3)"
	return 1
    }
    local imagefile="/tmp/$(basename "$0").$$.jpg"
    local eyeD3opts
    eyeD3opts=(
	"--artist=$1"
	"--title=$2"
        "$3"  # filename
        "--genre=$4"
        "--album=$6"
    )
    download "$5" "$imagefile" && eyeD3opts+=(
	"--add-image=$imagefile:ILLUSTRATION"
	"--add-image=$imagefile:ICON" )
    eyeD3 --remove-all "$filename" &>/dev/null
    eyeD3 "${eyeD3opts[@]}" -2 --force-update "$filename" &>/dev/null
    rm $imagefile
    echo '[i] Setting tags finished!'
}

function downsong() {
    # Grab Info
    url="$1"
    echo "[i] Grabbing song page"
    download "$url" | awk -F'"|<|>' '
	$3=="haudio large mode player" {id=$5}
	/<em itemprop="name">/ {getline; title=$0}
	$3=="byArtist" {artist=$21}
	$11=="genre search-deprecation-notification" {genre=$17}
	$3=="artwork-download-link" {imageurl=$7}
	$32=="clientID" {clientID=$34}
	#	   0	     1		  2	        3	     4		     5
	END {print id; print title; print artist; print genre; print imageurl; print clientID}
    ' | recode html..u8 | sed 's/\\u0026/\&/g' | (
	readarray -t songpage
	filename=$(echo "${songpage[1]}.mp3" | tr '*/\?"<>|' '+       ' )
	[ -e "$filename" ] && echo "[!] The song $filename has already been downloaded..." && return
	songurl=$(download "https://api.sndcdn.com/i1/tracks/${songpage[0]}/streams?client_id=${songpage[5]}" |
	    cut -d '"' -f 4 | sed 's/\\u0026/\&/g')
	imageurl="${songpage[4]/original/t500x500}"; imageurl="${imageurl/png/jpg}"
        echo "[-] Downloading ${songpage[1]}..."
	download -cv "$songurl" "$filename"
	settags "${songpage[2]}" "${songpage[1]}" "$filename" "${songpage[3]}" "$imageurl"
	echo "[i] Downloading of $filename finished"
	echo ''
    )
}

function downallsongs() {
    # Grab Info
    url="$1"
    echo "[i] Grabbing artists page"
    IDs=( $(download "$url" | sed -n '
	s/^.*"clientID":"\([a-z0-9]\+\)".*$/\1/p
	s#^.*http://api.soundcloud.com/users/\([0-9]\+\).*$#\1#p ') )
    clientID=${IDs[0]}; artistID=${IDs[1]} 
    echo "[i] Grabbing all song info"
    download "https://api.sndcdn.com/e1/users/$artistID/sounds?limit=256&offset=0&linked_partitioning=1&client_id=$clientID" | awk -F'<|>' '
	/^ {6}<kind>/ {kind=$3}
	/^ {6}<id / {print kind " " $3}
	kind=="track" && ($2~"^(genre|title|artwork-url)$") {print $3}
	kind=="playlist" && $2=="permalink-url" {print $3; kind=""}
    ' | recode html..u8 | while read kind id; do
	case "$kind" in
	    playlist)
		read playlisturl
		echo "[i] *--------Donwloading a set----------*"
		downset $playlisturl
		echo "[i] *-------- Set Downloaded -----------*"
		echo ''
	    ;;
	    track)
		read genre
		read title
		read imageurl
		filename=$(echo "$title".mp3 | tr '*/\?"<>|' '+       ' )
		[ -e "$filename" ] && echo "[!] The song $filename has already been downloaded..."  && continue
		echo "[-] Downloading the song $title..."
		songurl=$(download "https://api.sndcdn.com/i1/tracks/$id/streams?client_id=$clientID" | tee /dev/stderr | cut -d '"' -f 4 | sed 's/\\u0026/\&/g')
		download -cv "$songurl" "$(echo -e "$filename")"
		settags "$artist" "$title" "$filename" "$genre" "${imageurl/large/t500x500}"
		echo "[i] Downloading of $filename finished"
		echo ''
	    ;;
	esac
    done
}

function downgroup() {
    groupurl="$1"
    echo "[i] Grabbing group page"
    IDs=( $(download "$groupurl" | sed -n '
	s/^.*"clientID":"\([a-z0-9]\+\)".*$/\1/p
	s#^.*http://api.soundcloud.com/groups/\([0-9]\+\).*$#\1#p ') )
    clientID=${IDs[0]}; groupid=${IDs[1]}
    download "http://api.soundcloud.com/groups/$groupid/tracks.json?client_id=$clientID" \
	| tr '}' "\n" \
	| sed -n '/"kind":"user"/d; s/^.*"permalink_url":"\([^"]\+\)".*$/\1/p' \
	| while read thisongurl; do
	    downsong "$thisongurl"
	done
}

function downset() {
    # Grab Info
    echo "[i] Grabbing set page"
    url="$1"
    download "$url" | awk -F'"|<|>' '
	/<h1 class="with-artwork"/ {getline; print}
	/itemprop="numTracks"/ {print $5}
	$14==" data-sc-track=" {print $29}
	$6==" data-sc-track=" {print $21}
    ' | recode html..u8 | sed 's/\\u0026/\&/g' | (
	read settitle
	read numsongs
	echo "[i] Found set $settitle [$numsongs songs]"
        [ "$numsongs" -gt 0 ] || { echo "[!] No songs found"; exit 1; }
	while read songurl; do
	    downsong "http://soundcloud.com$songurl"
	done
    )
}

function downallsets() {
    allsetsurl="$1"
    echo "[i] Grabbing user sets page"
    allsetspage=$(download "$allsetsurl")
    allsetsnumpages=$(echo "$allsetspage" | grep '<li class="set">' | wc -l)
    echo "[i] $allsetsnumpages sets pages found"
    for (( allsetsnumcurpage=1; allsetsnumcurpage <= $allsetsnumpages; allsetsnumcurpage++ ))
    do
        echo "   [i] Grabbing user sets page $allsetsnumcurpage"
	allsetspage=$(download "$allsetsurl?page=$allsetsnumcurpage")
        allsetssets=$(echo "$allsetspage" | grep -A1 "li class=\"set\"" | grep "<h3>" | sed 's/.*href="\([^"]*\)">.*/\1/g')
        if [ -z "$allsetssets" ]; then
            echo "[!] No sets found on user sets page $allsetsnumcurpage"
            continue
        fi
        allsetssetscount=$(echo "$allsetssets" | wc -l)
        echo "[i] Found $allsetssetscount set(s) on user sets page $allsetsnumcurpage"
        for (( allsetsnumcurset=1; allsetsnumcurset <= $allsetssetscount; allsetsnumcurset++ ))
        do
            allsetsseturl=$(echo "$allsetssets" | sed -n "$allsetsnumcurset"p)
            echo "*-------- Downloading set n°$allsetsnumcurset ----------*"
            downset "http://soundcloud.com$allsetsseturl"
            echo "*-------- Set n°$allsetsnumcurset Downloaded -----------*"
        done
    done
}

function show_help() {
    cat <<END
[i] Usage: $(basename $0) [url] ...
    With url like :
        http://soundcloud.com/user (Download all of one user's songs)
        http://soundcloud.com/user/song-name (Download one single song)
        http://soundcloud.com/user/sets (Download all of one user's sets)
        http://soundcloud.com/user/sets/set-name (Download one single set)

   Downloaded file names like : title.mp3

END
}

if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ] ; then
    show_help
    exit 1
fi

writags=1
curlinstalled=$(command -v curl)
wgetinstalled=$(command -v wget)

if [ "$curlinstalled" ]; then
  echo "[i] Using" `curl -V` | cut -c-21
elif [ "$wgetinstalled" ]; then
  echo "[i] Using" `wget -V` | cut -c-24
  echo "[i] cURL is preferred" 
else
  echo "[!] cURL or Wget need to be installed."; exit 1;
fi

command -v recode &>/dev/null || { echo "[!] Recode needs to be installed."; exit 1; }
command -v eyeD3 &>/dev/null || { echo "[!] eyeD3 needs to be installed to write tags into mp3 file."; echo "[!] The script will skip this part..."; writags=0; }

while [ "$1" ]; do
    soundurl=$(echo "$1" | sed -n 's#^.*\(soundcloud.com/[^?]\+\).*$#http://\1#p')

    echo "[i] Using URL $soundurl"

    case "$soundurl" in
	http://soundcloud.com/groups/*)
	    echo "[i] Detected download type : All song of the group"
	    downgroup "$soundurl"
	    ;;
	http://soundcloud.com/*/sets/*)
	    echo "[i] Detected download type : One single set"
	    downset "$soundurl"
	    ;;
	http://soundcloud.com/*/sets)
	    echo "[i] Detected download type : All of one user's sets"
	    downallsets "$soundurl"
	    ;;
	http://soundcloud.com/*/*)
	    echo "[i] Detected download type : One single song"
	    downsong "$soundurl"
	    ;;
	http://soundcloud.com/*)
	    echo "[i] Detected download type : All of one user's songs"
	    downallsongs "$soundurl"
	    ;;
	*)
	    echo "[!] Bad URL: $1!"
	    show_help
	    exit 1
	    ;;
    esac
    shift
done
