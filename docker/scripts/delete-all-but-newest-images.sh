#!/bin/bash
################################################################################
# Delete all but the newest Docker images for each repository.
#
# Copyright 2021, 2024, 2025 William W. Kimball, Jr., MBA, MSIS
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
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
