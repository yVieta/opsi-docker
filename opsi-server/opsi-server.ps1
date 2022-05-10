
$context_dir = $(Split-Path -Path $PSCommandPath -Parent)
Set-Location -Path $context_dir


function od_prune {
	Write-Host "Prune containers, images and volumes"
	Write-Host -NoNewline "Are you sure? (y/n): "
	$key = $Host.UI.RawUI.ReadKey().Character
	Write-Host ""
	if ($key -eq "Y" -Or $key -eq "y") {
		od_stop
		$images = @()
		$out = docker-compose config
		$pattern = "\s*image:\s*([^\s]+)\s*"
		$matches = [regex]::Matches($out, $pattern)
		foreach ($match in $matches) {
			$images += $match.Groups[1].Value
		}
		Write-Host "Delete containers"
		docker-compose rm -f
		Write-Host "Delete volumes"
		docker volume prune -f
		$out = docker image ls "opsi-server*" --quiet
		Write-Host "Delete images"
		foreach($image in $images) {
			docker image rm --force $image
		}
	}
}

function od_start {
	Write-Host "Start containers"
	docker-compose up -d
}

function od_stop {
	Write-Host "Stop containers"
	docker-compose stop
}

function od_logs {
	param (
		$service
	)
	docker-compose logs -f $service
}

function od_shell {
	param (
		$service
	)
	$cmd = "sh"
	if (!$service) {
		$service = "opsi-server"
	}
	if ($service -eq "opsi-server") {
		$cmd = "zsh"
	}
	docker-compose exec $service $cmd
}

function od_update {
	docker-compose pull
	od_stop
	od_start
}

function od_export_images {
	$archive = "opsi-server-images.tar"
	if (Test-Path -Path $archive -PathType Leaf) {
		Remove-Item -Path $archive
	}
	$images = @()
	$out = docker-compose config
	$pattern = "\s*image:\s*([^\s]+)\s*"
	$matches = [regex]::Matches($out, $pattern)
	foreach ($match in $matches) {
		$images += $match.Groups[1].Value
	}
	if ($images.count -gt 0) {
		Write-Host "Exporting images $images to $archive"
		$archive = Join-Path $context_dir -ChildPath $archive
		docker save $images -o "$archive"
	}
	else {
		Write-Host "No images found to export"
	}
}

function od_import_images {
	param (
		$archive
	)
	if (-not(Test-Path -Path $archive -PathType Leaf)) {
		Write-Host "Archive $archive not found"
		exit 1
	}
	Write-Host "Importing images from $archive"
	docker load -i $archive
}

function od_usage {
	Write-Host "Usage: $(Split-Path -Path $PSCommandPath -Leaf) {start|stop|logs|shell|update|prune|export-images|import-images}"
	Write-Host ""
	Write-Host "  start                     Start all containers."
	Write-Host "  stop                      Stop all containers."
	Write-Host "  logs [service]            Attach to container logs (all logs or supplied service)."
	Write-Host "  shell [service]           Exexute a shell in the running container (default service: opsi-server)."
	Write-Host "  update                    Update and restart all containers."
	Write-Host "  prune                     Delete all containers and unassociated volumes."
	Write-Host "  export-images             Export images as archive."
	Write-Host "  import-images <archive>   Import images from archive."
	Write-Host ""
}

switch ($args[0]) {
	"start" {
		od_start
	}
	"stop" {
		od_stop
	}
	"logs" {
		od_logs $args[1]
	}
	"shell" {
		od_shell $args[1]
	}
	"update" {
		od_update
	}
	"prune" {
		od_prune
	}
	"export-images" {
		od_export_images
	}
	"import-images" {
		od_import_images $args[1]
	}
	default {
		od_usage
		exit 1
	}
}

exit 0
