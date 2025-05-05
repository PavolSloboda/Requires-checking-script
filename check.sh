#!/bin/bash

to_check=("mariadb-devel" "mysql-devel")
valid_file="valid.txt"
tarball_url="http://src.fedoraproject.org/repo/rpm-specs-latest.tar.xz"

#holds how old packges should be displayed (days from last build)
date_diff=365

search_tarball=false
search_dnf=true
alternate_tarball=false
get_tarball=false
check_valid=true
simplified_output=false
ingore_duplicates=false

tarball_location="."

help()
{
	echo "usage: ./check.sh [OPTION]"
	echo "a tool created to check for the Requires and BuildRequires of mariadb-devel and mysql-devel"
	echo "in packages on dnf and through the tarball of spec files"
	echo ''
	echo -e "\t-h, --help\t\tdisplays this help message and exits"
	echo -e "\t-f, --file\t\tfile of valid packages with their reasons"
	echo -e "\t-d, --days\t\tnumber of days since packages last update to check"
	echo -e "\t-t, --tar-ball\t\tsearch also in the tarball"
	echo -e "\t--no-dnf\t\tdo notsearch dnf"
	echo -e "\t--tarball-location\tlocation of the unpacked tarball of specs"
	echo -e "\t-a, --alternate-tarball\tsearch the tarball alternativelly (less acurate)"
	echo -e "\t-g, --get-tarball\tdownload and extract the tarball from src.fedoraproject.org"
	echo -e "\t-c, --to-check\t\tspecifies the dependecies to check for as a space or comma separated list"
	echo -e "\t-V, --no-check-valid\tdo not check the file of known valids"
	echo -e "\t-s, --simplified-output\tsimplify the output for to ease further usage"
	echo -e "\d-s, --ignore-duplicates\tignores packages already found during this search"
}

#arg handling
while [[ $# -gt 0 ]]; do
	case $1 in
		-h| --help)
			help
			exit 0
			;;
		-f|--file)
			valid_file="$2"
			shift
			shift
			;;
		-d|--days)
			date_diff="$2"
			shift
			shift
			;;
		-t|--tar-ball)
			search_tarball=true
			shift
			;;
		--no-dnf)
			search_dnf=false
			shift
			;;
		--tarball-location)
			tarball_location="$2"
			shift
			shift
			;;
		-a|--alternate_tarball)
			alternate_tarball=true
			shift
			;;
		-g|--get-tarball)
			get_tarball=true
			shift
			;;
		-c|--to-check)
			IFS=', ' read -r -a to_check <<< "$2"
			shift
			shift
			;;
		-V|--no-check-valid)
			check_valid=false
			shift
			;;
		-s|--simplify-output)
			simplified_output=true
			shift
			;;
		-i|--ignore-duplicates)
			ignore_duplicates=true
			shift
			;;
		*)
			echo "Unknown option $1"
			exit 1
			;;
	esac
done

if [[ "$ignore_duplicates" = true ]];
then
	declare -a already_found
fi

#should we take the known valids into consideration
if [[ "$check_valid" = true ]];
then
	#checks whether the file containing the known valids exists
	if [ ! -f "$valid_file" ];
	then
		echo "The file containing the known valids: ""$valid_file"" was not found"
		echo "for help use: ./check.sh -h|--help"
		exit 1
	fi

	declare -a valid
	#gets rid of reasons and stores the known valids in an array
	readarray -t valid <<< $(grep -Po ".*(?=\s-- )" "$valid_file")
fi

if [[ "$search_tarball" = true ]];
then
	#gets and extracts the tarball
	if [[ "$get_tarball" = true ]];
	then
		cd "$tarball_location" && wget "$tarball_url"
		tar -xf rpm-specs-latest.tar.xz
		cd - &>/dev/null
	fi

	#checks whether the tarball location exists and contains the expected dir
	if [ ! -d "$tarball_location""/rpm-specs" ];
	then
		echo "Tarball not found at '""$tarball_location""'"
		echo "You can download and unpack it using the \`-g|--get-tarball\` param"
		echo "or specify it's location using the \`--tarball-location /path/to/tarball\` param"
		exit 1
	fi
fi

#searches dnf for what requires the specified packages
#with the alldeps param
if [[ "$search_dnf" = true ]];
then
	for i in "${to_check[@]}"
	do
		if [[ "$simplified_output" = false ]];
		then
			echo $i
			echo "--------------------------------------"
		fi
		declare -a found
		readarray -t found <<< $(sudo dnf --repo=rawhide --repo=rawhide-source repoquery --whatrequires "$i" --queryformat '%{buildtime}: %{name}-%{epoch}:%{version}-%{release}.%{arch}\n' 2>/dev/null)

		for j in "${found[@]}"
		do
			#checks if the package is not in valid and prints it
			if [[ "$check_valid" = false || ! " ${valid[*]} " =~ [[:space:]]$(echo $j | grep -Po "[A-Za-z-]*(?=-\d:\d)")[[:space:]] ]];
			then
				#checks whether the package had it's last build in the last $date_dif
				#days and displays it
				if [[ $(date --date="$(date) -${date_diff} day" +%Y-%m-%d) < $(date -d @$(echo $j | grep -Po ".*(?=: )")) ]]
				then
					if [[ "$ignore_duplicates" = true ]];
					then
						if [[ ! " ${already_found[*]} " =~ [[:space:]]$(echo $j | grep -Po "[A-Za-z-]*(?=-\d:\d)")[[:space:]] ]];
						then
							echo $j | grep -Po "(?<=\: ).*"
							already_found+=" "
							already_found+=$(echo $j | grep -Po "(?<=\: ).*(?=-\d:)")
						fi
					else
						echo $j | grep -Po "(?<=\: ).*"
					fi
				fi
			fi
		done
		if [[ "$simplified_output" = false ]];
		then
			#for the newline after each group
			echo ''
		fi
	done
fi

if [[ "$search_tarball" = true ]]; then
	if [[ "$simplified_output" = false ]];
	then
		echo "The occurences in the tarball:"
		echo "++++++++++++++++++++++++++++++"
	fi
	#searches the tarball in a broader but less accurate way
	if [[ "$alternate_tarball" = true ]];
	then
		for i in "${to_check[@]}"
		do
			declare -a found
			declare -a found_req
			if [[ "$simplified_output" = false ]];
			then
				echo ${i}
				echo "--------------------------------------"
				echo "BuildRequires:"
				echo "----------------------"
			fi
			readarray -t found <<< $(cd "$tarball_location""/rpm-specs" && grep -H "$i" ./* | grep ":\s*BuildRequires:" | grep -v "mariadb-connector-c" | grep -vP "^\s*#")
			for x in "${found[@]}"
			do 
				if [[ "$check_valid" = false || ! " ${valid[*]} " =~ [[:space:]]$(echo $x | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")[[:space:]] ]]; then
					if [[ "$ignore_duplicates" = true ]];
					then

						if [[ ! " ${already_found[*]} " =~ [[:space:]]$(echo $x | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")[[:space:]] ]];
						then
							echo $x
							already_found+=" "
							already_found+=$(echo $x | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")
						fi
					else
						echo $x
					fi
				fi
			done
			if [[ "$simplified_output" = false ]];
			then
				echo ''
				echo "Requires:"
				echo "----------------------"
			fi
			readarray -t found <<< $(cd "$tarball_location""/rpm-specs" && grep -H "$i" ./* | grep -P ":\s*Requires:" | grep -v "mariadb-connector-c" | grep -vP "^\s*#")
			for x in "${found[@]}"
			do 
				if [[ "$check_valid" = false || ! " ${valid[*]} " =~ [[:space:]]$(echo $x | grep -Po "(?<=\./).*(?=\.spec:Requires)")[[:space:]] ]]; then
					if [[ "$ignore_duplicates" = true ]];
					then

						if [[ ! " ${already_found[*]} " =~ [[:space:]]$(echo $x | grep -Po "(?<=\./).*(?=\.spec:Requires)")[[:space:]] ]];
						then
							echo $x
							already_found+=" "
							already_found+=$(echo $x | grep -Po "(?<=\./).*(?=\.spec:Requires)")
						fi
					else
						echo $x
					fi
				fi
			done
			if [[ "$simplified_output" = false ]];
			then
				echo ''
			fi
		done
	#checks the tarball in a less broad way but with fewer false positives
	else
		for i in "${to_check[@]}"
		do
			declare -a found
			declare -a found_req
			if [[ "$simplified_output" = false ]];
			then
				echo $i
				echo "--------------------------------------"
				echo "BuildRequires:"
				echo "----------------------"
			fi
			readarray -t found <<< $(cd "$tarball_location""/rpm-specs" && grep -HP "(?<!#)BuildRequires:\s*$i" ./*)
			#checks if the package is not in valid and prints it
			for j in "${found[@]}"
			do 
				if [[ "$check_valid" = false || ! " ${valid[*]} " =~ [[:space:]]$(echo $j | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")[[:space:]] ]]; then
					if [[ "$ignore_duplicates" = true ]];
					then

						if [[ ! " ${already_found[*]} " =~ [[:space:]]$(echo $j | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")[[:space:]] ]];
						then
							echo $j
							already_found+=" "
							already_found+=$(echo $j | grep -Po "(?<=\./).*(?=\.spec:BuildRequires)")
						fi
					else
						echo $j
					fi
				fi
			done
			if [[ "$simplified_output" = false ]];
			then
				echo ''
				echo "Requires:"
				echo "----------------------"
			fi
			readarray -t found <<< $(cd "$tarball_location""/rpm-specs" && grep -HP "(?<!Build|#)Requires:\s*$i" ./*)
			#checks if the package is not in valid and prints it
			for j in "${found[@]}"
			do 
				if [[ "$check_valid" = false || ! " ${valid[*]} " =~ [[:space:]]$(echo $j | grep -Po "(?<=\./).*(?=\.spec:Requires)")[[:space:]] ]]; then
					if [[ "$ignore_duplicates" = true ]];
					then
						if [[ ! " ${already_found[*]} " =~ [[:space:]]$(echo $j | grep -Po "(?<=\./).*(?=\.spec:Requires)")[[:space:]] ]];
						then
							echo $j
							already_found+=" "
							already_found+=$(echo $j | grep -Po "(?<=\./).*(?=\.spec:Requires)")
						fi
					else
						echo $j
					fi
				fi
			done
			if [[ "$simplified_output" = false ]];
			then
				echo ''
			fi
		done
	fi
fi
