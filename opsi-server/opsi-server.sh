#!/bin/bash

PROJECT_NAME="opsi-server"
IMAGE_NAME="opsi-server"
DEFAULT_SERVICE="opsi-server"
[ -z $REGISTRY ] && REGISTRY="docker.io"
[ -z $REGISTRY_PATH ] && REGISTRY_PATH=""
[ -z $REGISTRY_USERNAME ] && REGISTRY_USERNAME=""
[ -z $REGISTRY_PASSWORD ] && REGISTRY_PASSWORD=""
[ -z $OPSI_VERSION ] && OPSI_VERSION="4.3"
[ -z $OPSI_BRANCH ] && OPSI_BRANCH="stable"
[ -z $COMPOSE_URL ] && COMPOSE_URL="https://raw.githubusercontent.com/opsi-org/opsi-docker/main/opsi-server/docker-compose.yml"
[ -z $ADDITIONAL_TAGS ] && ADDITIONAL_TAGS=""
IMAGE_TAG="${OPSI_VERSION}-${OPSI_BRANCH}"

DOCKER_COMPOSE="docker-compose"
which $DOCKER_COMPOSE >/dev/null || DOCKER_COMPOSE="docker compose"

cd $(dirname "${BASH_SOURCE[0]}")

function od_build {
	echo "Build ${IMAGE_NAME}:${IMAGE_TAG}" 1>&2
	docker build $1 \
		--tag "${IMAGE_NAME}:${IMAGE_TAG}" \
		--build-arg OPSI_VERSION=$OPSI_VERSION \
		--build-arg OPSI_BRANCH=$OPSI_BRANCH \
		.
}


function od_publish {
	prefix="${REGISTRY}"
	[ -z $prefix ] || prefix="${prefix}/"
	prefix="${prefix}${REGISTRY_PATH##*/}"

	auth=""
	if [ ! -z $REGISTRY_USERNAME ]; then
		auth="${auth} --username ${REGISTRY_USERNAME}"
		[ -z $REGISTRY_PASSWORD ] || auth="${auth} --password-stdin"
	fi

	echo "Publish ${IMAGE_NAME}:${IMAGE_TAG} in '${prefix}'" 1>&2

	set -e
	[ -z "${auth}" ] || docker login ${REGISTRY} ${auth} <<< "${REGISTRY_PASSWORD}"

	opsiconfd_version=$(docker run -e OPSI_HOSTNAME=opsiconfd.opsi.org --entrypoint /usr/bin/opsiconfd "${IMAGE_NAME}:${IMAGE_TAG}" --version | cut -d' ' -f1)

	for tag in ${IMAGE_TAG} ${opsiconfd_version} ${ADDITIONAL_TAGS}; do
		echo docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${prefix}/${IMAGE_NAME}:${tag}"
		docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${prefix}/${IMAGE_NAME}:${tag}"
	done

	echo docker push -a "${prefix}/${IMAGE_NAME}"
	docker push -a "${prefix}/${IMAGE_NAME}"

	echo docker images "${prefix}/${IMAGE_NAME}"
	docker images "${prefix}/${IMAGE_NAME}"
}


function od_prune {
	echo "Prune ${PROJECT_NAME} containers, networks and volumes" 1>&2
	read -p "Are you sure? (y/n): " -n 1 -r
	echo ""
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "${DOCKER_COMPOSE} down -v" 1>&2
		${DOCKER_COMPOSE} down -v
	fi
}


function od_download_compose {
	echo "Download docker-compose.yml" 1>&2
	if ! wget "${COMPOSE_URL}" --no-verbose -O docker-compose.yml; then
		[ -e docker-compose.yml ] && rm docker-compose.yml
		echo "Download failed" 1>&2
		exit 1
	fi
}


function od_start {
	[ -e "docker-compose.yml" ] || od_download_compose
	echo "Start containers" 1>&2
	echo "${DOCKER_COMPOSE} up -d" 1>&2
	${DOCKER_COMPOSE} up -d
}


function od_status {
	echo "${DOCKER_COMPOSE} ps"
	${DOCKER_COMPOSE} ps
}


function od_stop {
	echo "Stop containers" 1>&2
	echo "${DOCKER_COMPOSE} stop" 1>&2
	${DOCKER_COMPOSE} stop
}


function od_recreate {
	echo "Remove containers" 1>&2
	echo "${DOCKER_COMPOSE} down" 1>&2
	${DOCKER_COMPOSE} down
	echo "Create and start containers" 1>&2
	echo "${DOCKER_COMPOSE} up --force-recreate -d" 1>&2
	${DOCKER_COMPOSE} up --force-recreate -d
}


function od_logs {
	echo "${DOCKER_COMPOSE} logs -f $1" 1>&2
	${DOCKER_COMPOSE} logs -f $1
}


function od_shell {
	service="$1"
	cmd="sh"
	[ -z $service ] && service=$DEFAULT_SERVICE
	[ $service = "opsi-server" ] && cmd="zsh"
	echo "${DOCKER_COMPOSE} exec $service $cmd" 1>&2
	${DOCKER_COMPOSE} exec $service $cmd
}


function od_upgrade {
	echo "${DOCKER_COMPOSE} pull" 1>&2
	${DOCKER_COMPOSE} pull || exit 1
	od_recreate
}


function od_export_images {
	archive="${PROJECT_NAME}-images.tar.gz"
	[ -e "${archive}" ] && rm "${archive}"
	images=( $(${DOCKER_COMPOSE} config | grep "image:" | sed s'/.*image:\s*//' | tr '\n' ' ') )
	if [ ${#images[@]} -gt 0 ]; then
		echo "Exporting images ${images[@]} to ${archive}" 1>&2
		echo "docker save ${images[@]} | gzip > \"${archive}\"" 1>&2
		docker save ${images[@]} | gzip > "${archive}"
	else
		echo "No images found to export" 1>&2
	fi
}


function od_import_images {
	archive="$1"
	[ -z $archive ] && archive="${PROJECT_NAME}-images.tar.gz"
	if [ ! -e "${archive}" ]; then
		echo "Archive ${archive} not found" 1>&2
		exit 1
	fi
	echo "Importing images from ${archive}" 1>&2
	echo "docker load -i \"${archive}\"" 1>&2
	docker load -i "${archive}"
}


function od_open_volumes {
	sudo sleep 0.1 # to get auth
	sudo xdg-open /var/lib/docker/volumes >/dev/null 2>&1 &
}


function od_edit {
	xdg-open docker-compose.yml >/dev/null 2>&1 &
}


function od_inspect {
	service="$1"
	[ -z $service ] && service=$DEFAULT_SERVICE
	echo "docker inspect ${PROJECT_NAME}_${service}_1" 1>&2
	docker inspect ${PROJECT_NAME}_${service}_1
}


function od_diff {
	service="$1"
	[ -z $service ] && service=$DEFAULT_SERVICE
	echo "docker diff ${PROJECT_NAME}_${service}_1" 1>&2
	docker diff ${PROJECT_NAME}_${service}_1
}


function od_usage {
	echo "Usage: $0 <command>"
	echo ""
	echo "Commands:"
	echo "  download-compose          Download docker-compose.yml from repository."
	echo "  edit                      Edit docker-compose.yml."
	echo "  start                     Start all containers."
	echo "  status                    Show running containers."
	echo "  stop                      Stop all containers."
	echo "  recreate                  Recreate all containers (needed after changing docker-compose.yml)."
	echo "  logs [service]            Attach to container logs (all logs or supplied service)."
	echo "  shell [service]           Exexute a shell in a running container (default service: ${DEFAULT_SERVICE})."
	echo "  upgrade                   Upgrade and restart all containers."
	echo "  open-volumes              Open volumes directory in explorer."
	echo "  inspect [service]         Show detailed container informations (default service: ${DEFAULT_SERVICE})."
	echo "  diff [service]            Show container's filesystem changes (default service: ${DEFAULT_SERVICE})."
	echo "  prune                     Delete all containers and unassociated volumes."
	echo "  export-images             Export images as archive."
	echo "  import-images [archive]   Import images from archive."
	echo "  build [--no-cache]        Build ${IMAGE_NAME} image. Use --no-cache to build without cache."
	echo "  publish                   Publish ${IMAGE_NAME} image."
	echo ""
}


case $1 in
	"download-compose")
		od_download_compose
	;;
	"edit")
		od_edit
	;;
	"start")
		od_start
	;;
	"status")
		od_status
	;;
	"stop")
		od_stop
	;;
	"recreate")
		od_recreate
	;;
	"logs")
		od_logs $2
	;;
	"shell")
		od_shell $2
	;;
	"upgrade")
		od_upgrade
	;;
	"open-volumes")
		od_open_volumes
	;;
	"inspect")
		od_inspect $2
	;;
	"diff")
		od_diff $2
	;;
	"prune")
		od_prune
	;;
	"export-images")
		od_export_images
	;;
	"import-images")
		od_import_images $2
	;;
	"build")
		od_build $2
	;;
	"publish")
		od_publish
	;;
	*)
		od_usage
		exit 1
	;;
esac

exit 0
