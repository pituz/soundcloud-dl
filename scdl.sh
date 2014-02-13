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
    local verbose
    if [ "$1" = "-v" ]; then
	verbose=1
	shift
    fi
    if $curlinstalled; then
	[ "$verbose" ] && verbose="-#" || verbose="-s"
        curl $verbose -L --user-agent 'Mozilla/5.0' "$1" -o "${2--}"
    else
	[ "$verbose" ] && verbose="--progress=bar" || verbose="-q"
        wget $verbose --max-redirect=1000 --trust-server-names -U 'Mozilla/5.0' -O "${2--}" "$1"
    fi
}

function settags() {
    artist=$1
    title=$2
    filename=$3
    genre=$4
    imageurl=$5
    album=$6
    download "$imageurl" "/tmp/1.jpg"
    if [ "$writags" = "1" ] ; then
        eyeD3 --remove-all "$filename" &>/dev/null
        eyeD3 --add-image="/tmp/1.jpg:ILLUSTRATION" --add-image="/tmp/1.jpg:ICON" -a "$artist" -Y $(date +%Y) -G "$genre" -t "$title" -A "$album" -2 --force-update "$filename" &>/dev/null
        echo '[i] Setting tags finished!'
    else
        echo "[i] Setting tags skipped (please install eyeD3)"
    fi
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
        echo "[-] Downloading $title..."
	download -v "$songurl" "$filename"
	settags "${songpage[2]}" "${songpage[1]}" "$filename" "${songpage[3]}" "$imageurl"
	echo "[i] Downloading of $filename finished"
	echo ''
    )
}

function downallsongs() {
    # Grab Info
    url="$1"
    echo "[i] Grabbing artists page"
    page=$(download "$url")
    clientID=$(echo "$page" | grep "clientID" | tr "," "\n" | grep "clientID" | cut -d '"' -f 4)
    artistID=$(echo "$page" | tr "," "\n" | grep "trackOwnerId" | head -n 1 | cut -d ":" -f 2) 
    echo "[i] Grabbing all song info"
    songs=$(download "https://api.sndcdn.com/e1/users/$artistID/sounds?limit=256&offset=0&linked_partitioning=1&client_id=$clientID"  | tr -d "\n" | sed 's/<stream-item>/\n/g' | sed '1d' )
    songcount=$(echo "$songs" | wc -l)
    echo "[i] Found $songcount songs! (200 is max)"
    if [ -z "$songs" ]; then
        echo "[!] No songs found at $1" && exit
    fi
    echo ""
    for (( i=1; i <= $songcount; i++ ))
    do
        playlist=$(echo -e "$songs"| sed -n "$i"p | tr ">" "\n" | grep "</kind" | cut -d "<" -f 1 | grep playlist)
        if [ "$playlist" = "playlist" ] ; then 
            playlisturl=$(echo -e "$songs" | sed -n "$i"p | tr ">" "\n" | grep "</permalink-url" | cut -d "<" -f 1 | head -n 1 | recode html..u8)
            echo "[i] *--------Donwloading a set----------*"
            downset $playlisturl
            echo "[i] *-------- Set Downloaded -----------*"
            echo ''
        else
            title=$(echo -e "$songs" | sed -n "$i"p | tr ">" "\n" | grep "</title" | cut -d "<" -f 1 | recode html..u8)
            filename=$(echo "$title".mp3 | tr '*/\?"<>|' '+       ' )
            if [ -e "$filename" ]; then
                echo "[!] The song $filename has already been downloaded..."  && continue
            fi
            artist=$(echo "$songs" | sed -n "$i"p | tr ">" "\n" | grep "</username" | cut -d "<" -f 1 | recode html..u8)
            genre=$(echo "$songs" | sed -n "$i"p | tr ">" "\n" | grep "</genre" | cut -d "<" -f 1 | recode html..u8)
            imageurl=$(echo "$songs" | sed -n "$i"p | tr ">" "\n" | grep "</artwork-url" | cut -d "<" -f 1 | sed 's/large/t500x500/g')
            songID=$(echo "$songs" | sed -n "$i"p | tr " " "\n" | grep "</id>" | head -n 1 | cut -d ">" -f 2 | cut -d "<" -f 1)
            # DL
            echo "[-] Downloading the song $title..."
	    songurl=$(download "https://api.sndcdn.com/i1/tracks/$songID/streams?client_id=$clientID" | cut -d '"' -f 4 | sed 's/\\u0026/\&/g')
	    download -v "$songurl" "$(echo -e "$filename")"
            settags "$artist" "$title" "$filename" "$genre" "$imageurl"
            echo "[i] Downloading of $filename finished"
            echo ''
        fi
    done
}

function downgroup() {
    groupurl="$1"
    echo "[i] Grabbing group page"
    grouppage=$(download "$groupurl")
    groupid=$(echo "$groupage" | grep "html5-code-groups" | tr " " "\n" | grep "html5-code-groups-" | cut -d '"' -f 2 | sed '2d' | cut -d '-' -f 4)
    clientID=$(echo "$groupage" | grep "clientID" | tr "," "\n" | grep "clientID" | cut -d '"' -f 4)
    trackspage=$(curl -L -s --user-agent 'Mozilla/5.0' "http://api.soundcloud.com/groups/$groupid/tracks.json?client_id=$clientID" | tr "}" "\n")
    trackspage=$(echo "$trackspage" | tr "," "\n" | grep '"permalink_url":' | sed '1d' | sed -n '1~2p')
    songcount=$(echo "$trackspage" | wc -l)
    echo "[i] Found $songcount songs!"
    for (( i=1; i <= $songcount; i++ ))
    do
        echo ''
        echo "---------- Downloading Song n°$i ----------"
        thisongurl=$(echo "$trackspage" | sed -n "$i"p | cut -d '"' -f 4)
        downsong "$thisongurl"
        echo "----- Downloading Song n°$i finished ------"
    done
}

function downset() {
    # Grab Info
    echo "[i] Grabbing set page"
    url="$1"
    page=$(download "$url")
    settitle=$(echo -e "$page" | grep -A1 "<em itemprop=\"name\">" | tail -n1) 
    setsongs=$(echo "$page" | grep -oE "data-sc-track=.[0-9]*" | grep -oE "[0-9]*" | sort | uniq) 
    clientID=$(echo "$page" | awk -F'"|<|>' '$32=="clientID" {print $34}')
    echo "[i] Found set "$settitle""
    if [ -z "$setsongs" ]; then
        echo "[!] No songs found"
        exit 1
    fi
    songcountset=$(echo "$setsongs" | wc -l)
    echo "[i] Found $songcountset songs"
    echo ""
    for (( numcursong=1; numcursong <= $songcountset; numcursong++ ))
    do
        id=$(echo "$setsongs" | sed -n "$numcursong"p)
        title=$(echo -e "$page" | grep data-sc-track | grep $id | grep -oE 'rel=.nofollow.>[^<]*' | sed 's/rel="nofollow">//' | sed 's/\\u0026/\&/g' | recode html..u8)
        if [[ "$title" == "Play" ]] ; then
        title=$(echo -e "$page" | grep $id | grep id | grep -oE "\"title\":\"[^\"]*" | sed 's/"title":"//' | sed 's/\\u0026/\&/g' | recode html..u8)
        fi
        artist=$(echo "$page" | grep -A3 $id | grep byArtist | cut -d"\"" -f2 | recode html..u8)
        filename=$(echo "$title".mp3 | tr '*/\?"<>|' '+       ' )      
        if [ -e "$filename" ]; then
            echo "[!] The song $filename has already been downloaded..."  && continue
        else
            echo "[-] Downloading $title..."
        fi
        #----------settags-------#
        pageurl=$(echo "$page" | grep -A3 $id | grep url | cut -d"\"" -f2)
        if $curlinstalled; then
        songpage=$(curl -s -L --user-agent 'Mozilla/5.0' "$pageurl")
        else
        songpage=$(wget --max-redirect=1000 --trust-server-names --progress=bar -U -O- 'Mozilla/5.0' "$pageurl")
        fi
        imageurl=$(echo "$songpage" | tr ">" "\n" | grep -A1 '<div class="artwork-download-link"' | cut -d '"' -f 2 | tr " " "\n" | grep 'http' | sed 's/original/t500x500/g' | sed 's/png/jpg/g' )
        genre=$(echo "$songpage" | tr ">" "\n" | grep -A1 '<span class="genre search-deprecation-notification" data="/tags/' | tr ' ' "\n" | grep '</span' | cut -d "<" -f 1 | recode html..u8)
        album=$(echo "$page" | sed s/'<meta content='/\n/g | grep 'property="og:title"' | cut -d '=' -f 4 | cut -d '"' -f 4 | recode html..u8)
        #------------------------#
        # DL
	songurl=$(download "https://api.sndcdn.com/i1/tracks/$id/streams?client_id=$clientID" | cut -d '"' -f 4 | sed 's/\\u0026/\&/g')
	download -v "$songurl" "$(echo -e "$filename")"
        settags "$artist" "$title" "$filename" "$genre" "$imageurl" "$album"
        echo "[i] Downloading of $filename finished"
        echo ''
    done
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
curlinstalled=`command -V curl &>/dev/null`
wgetinstalled=`command -V wget &>/dev/null`

if $curlinstalled; then
  echo "[i] Using" `curl -V` | cut -c-21
elif $wgetinstalled; then
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
