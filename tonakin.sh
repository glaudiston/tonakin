#!/bin/bash

encode_array()
{
	for item in "$@";
	do
		echo -n "$item" | base64
	done | paste -s -d , -
}

decode_array()
{
	local IFS=$'\2'

	local i=0;
	local -a arr=($(echo "$1" | tr , "\n" |
		while read encoded_array_item;
		do 
			[ $i -gt 0 ] && echo $'\2'
			echo  "$encoded_array_item" | base64 -d;
			let i++;
		done))
	echo "${arr[*]}";
}

test_arrays_step1()
{
	local -a arr1=($(decode_array "$1"| tr -d $'\2'))
	local -a arr2=($(decode_array "$2"| tr -d $'\2'))
	local -a arr3=($(decode_array "$3"| tr -d $'\2'))
	echo arr1 has ${#arr1[@]} items, the second item is ${arr1[1]} 
	echo arr2 has ${#arr2[@]} items, the third item is ${arr2[2]} 
	echo arr3 has ${#arr3[@]} items, the here the contents ${arr3[@]} 
	echo "${arr1[@]}" | xxd >&2
}

test_arrays()
{
	local a1_2="$(echo -en "c\td")";
	local a1=("a b" "$a1_2" "e f");
	local a2=(gh ij kl nm);
	local a3=(op ql );
	local a1_size=${#a1[@])};
	local resp=$(test_arrays_step1 "$(encode_array "${a1[@]}")" "$(encode_array "${a2[@]}")" "$(encode_array "${a3[@]}")");
	echo -e "$resp" | grep arr1 | grep "arr1 has $a1_size, the second item is $a1_2" || echo but it should have only $a1_size items, with the second item as $a1_2
	echo "$resp"
}
#test_arrays
#exit $?


# given a record line, a desired feature list and a non desired feature list, 
# return the record only if matches the desired features but not the non desired ones.
filter_only_desired()
{
	local record_line="$1";
	local desired_features=($(decode_array "$2"| tr -d $'\2'));
	local avoided_features=($(decode_array "$3"| tr -d $'\2'));

	if [ -z "${record_line}" ]; then
		# no data input, no output.
		return;
	fi;

	if [ -z "${desired_features}" -a -z "${avoided_features}" ]; then
		# given we have no filters, just dump everyting
		echo "${record_line}";
		return;
	fi;

	local match_data="${record_line}";
	if [ -n "${desired_features}" -a "${#desired_features[@]}" -gt 0 ]; then
		for feature in "${desired_features[@]}"; 
		do
			match_data=$(echo "${match_data}" | grep -F "${feature}" );
			if [ -z "$match_data" ]; then
				return
			fi;
		done;
	fi;

	if [ -n "${avoided_features}" -a "${#avoided_features[@]}" -gt "0" ]; then
		match_data=$(echo "${match_data}" | grep -vE "($(IFS='|';echo "${avoided_features[*]}"))" )
	fi;
	echo "$match_data"
}
test_filter_only_desired()
{
	local desired=(c)
	filter_only_desired "a,b,c,d,e" "$(encode_array "${desired[@]}")"
	filter_only_desired "b" $(encode_array "${desired[@]}")
}

#test_filter_only_desired;

# this function get the data from the input (stdin) filtering all entryies that has the feature list
filter_answers_with_current_features()
{
	local desired_features=($(decode_array "$1"| tr -d $'\2'))
	local avoided_features=($(decode_array "$2"| tr -d $'\2'))
	while read dataline; 
	do
		filter_only_desired "$dataline" "$(encode_array "${desired_features[@]}")" "$(encode_array "${avoided_features[@]}")";
	done | grep -vE '^$';
}

count_possibilities()
{
	cat datafile | wc -w
}

save_answer() 
{
	local answer="$1"
	local IFS=$'\2';
	local -a desired_features=($(decode_array "$2" | tr -d "\n"))
	unset IFS;
	echo "${#desired_features[@]}" >&2
	echo "$answer,$(IFS=$','; echo "${desired_features[*]}")" >> datafile
}

work_on_possibilities()
{
	echo "Hum..." >&2;

	local possibilities="$( filter_answers_with_current_features "$(encode_array "${desired_features[@]}")" "$(encode_array "${avoided_features[@]}")" <&3)"

	items=$( echo "$possibilities"  | grep -vE '^$' | wc -l)
	if [ -z "$possibilities" ]; then
		read -p "I have no enough data. can you please telme what are you thinking about: " answer < /dev/stdin >&2
		read -p "give me one feature of data that differ from everything else: " feature < /dev/stdin >&2
		desired_features[${#desired_features[@]}]="$feature"
		save_answer "$answer" "$(encode_array "${desired_features[@]}")"
		echo "$answer has $feature! I'll remember that!" >&2;
		echo . >&2
		echo "let's try again" >&2;
		if [ -z "$features" ]; then
			features="$feature";
		else
			features="$features|$feature";
		fi;
		continue;
	fi
	if [ "$items" -eq 1 ]; then
		echo -e " it is [$possibilities]" >&2;
		read -p "am i correct ? " resp >&2;
		if [ "$resp" == "yes" ]; then
			echo I knew it! thank you for playing. >&2;
		else
			read -p "why not? give me one feature of your answer, that $( echo $possibilities | sed "s/,/, that /g"), DOES NOT applies: " feature >&2;
			read -p "understood. what is the correct answer?" answer >&2;
			desired_features[${#desired_features[@]}]="$feature";
			save_answer "$answer" "$(encode_array "${desired_features[@]}")";
		fi;
		echo GAME_OVER
		return;
	fi;
	if [ "$items" -gt 1 ]; then
		echo I have $items possible solutions in this context... >&2
		selected_feature="$(echo "$possibilities"| cut -d, -f2- | tr , '\n' | 
			{
				temparr=( ${ignored_features[*]} ${desired_features[*]} ${avoided_features} )
				ignored_regex=$(IFS='|';echo "${temparr[*]}" | tr -d '\2' | tr -d '\n');
				if [ -n "${ignored_regex}" ]; then 
					grep -vE "($ignored_regex)"; 
				else 
					cat; 
				fi;
			} |
			sort | uniq -c | sort -n | 
			# { [ "$(( RANDOM % 2 ))" == 1 ] && head -1 || tail -1; } |
			tail -1 |
			tr -s " " | cut -d" " -f3-)";

		if [ -z "${selected_feature}" ]; then
			# no more bullets
			possibilities="";
		else
			echo "it is somehow related or kind of: $selected_feature ? " >&2
			read
			if [ "$REPLY" == yes ]; then
				# add it as a desired feature;
				desired_features[${#desired_features[@]}]="$selected_feature";
			elif [ "$REPLY" == no ]; then
				# add it as a avoided feature;
				avoided_features[${#avoided_features[@]}]="$selected_feature";
			else
				# echo "invalid response, i will ignore this feature" >&2
				# add it to ignored features
				ignored_features[${#ignored_features[@]}]="$selected_feature";
			fi;
			echo "$(echo "${possibilities}" | base64),$( encode_array "${desired_features[@]}" | base64),$( encode_array "${avoided_features[@]}" | base64),$( encode_array "${ignored_features[@]}" | base64)";
		fi;
		return;
	fi;
}

main()
{
	local possibilities="$(cat datafile)";
	local -a desired_features;
	local -a avoided_features;
	local -a ignored_features;
	local running=true
	while $running;
	do
		round_output="$(
			work_on_possibilities \
			"$(encode_array "${desired_features[@]}")" \
			"$(encode_array "${avoided_features[@]}")" \
			3<<<"$possibilities"
		)";
		if [ "${round_output}" == "GAME_OVER" ]; then
			return;
		fi;
		possibilities="$( echo "${round_output}" | cut -d, -f1 | base64 -d )";

		local IFS=$'\2'
		desired_features=($( decode_array "$( echo "${round_output}" | cut -d, -f2 | base64 -d )"));
		avoided_features=($( decode_array "$( echo "${round_output}" | cut -d, -f3 | base64 -d )"));
		ignored_features=($( decode_array "$( echo "${round_output}" | cut -d, -f4 | base64 -d )"));
		unset IFS;
	done;
}

main
