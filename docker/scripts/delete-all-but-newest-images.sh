#!/bin/bash
################################################################################
# Delete all but the newest Docker images for each repository.
################################################################################
# Get all images grouped by repository, keeping only the newest
docker images --format "{{.Repository}}:{{.Tag}}" \
	| grep -v '<none>' \
	| sort \
	| uniq \
	| while read image
do
	repo=$(echo "$image" | cut -d: -f1)

	# Get all tags for this repository, sorted by creation date (newest first)
	tags=$(docker images "$repo" --format "{{.Tag}}\t{{.CreatedAt}}" | sort -k2r | cut -f1)

	# Keep the first (newest) tag and delete the rest
	echo "$tags" | tail -n +2 | while read tag; do
		if [ "$tag" != "latest" ]; then
			echo "Removing $repo:$tag"
			docker rmi --force "$repo:$tag" 2>/dev/null ||:
		fi
	done
done
