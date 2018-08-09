SHELL := /bin/bash
REV_FILE=.make-rev-check
IMAGE_NAMESPACE=rotisserie

## Workflow
## export APP_HOSTNAME=''
##
## edit -
##	 letsencrypt.yaml
##   rotisserie-secrets.yaml
##
##
## Start from scratch(using kube-lego):
##	 make full-roll
##
## Start from scratch(without kube-lego):
##	 make roll
##
## Redeploying after making changes:
## 	 make all-images
##	 make redeploy
##
## Cleanup after testing:
##	 make purge

## IMAGES ##

# Sets the revision and stores it in .make-rev-check.
set-rev:
	git rev-parse --short HEAD > $(REV_FILE)

# Creates images for the app, ocr, and static containers. Runs set-rev to ensure that the rev_file exists.
images: set-rev
	./deploy/images/make-image.sh deploy/images/app.Dockerfile "rotisserie-app:$$(cat $(REV_FILE))"
	./deploy/images/make-image.sh deploy/images/ocr.Dockerfile "rotisserie-ocr:$$(cat $(REV_FILE))"
	./deploy/images/make-image.sh deploy/images/static-server.Dockerfile "rotisserie-static:$$(cat $(REV_FILE))"
	./deploy/images/make-image.sh deploy/images/processor.Dockerfile "rotisserie-sp:$$(cat $(REV_FILE))"

# Tags images for the app, ocr, and static containers. Runs set-rev to ensure that the rev_file exists.
tag-images: set-rev
	docker tag "rotisserie-app:$$(cat $(REV_FILE))" "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-app:$$(cat $(REV_FILE))"
	docker tag "rotisserie-ocr:$$(cat $(REV_FILE))" "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-ocr:$$(cat $(REV_FILE))"
	docker tag "rotisserie-static:$$(cat $(REV_FILE))" "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-static:$$(cat $(REV_FILE))"
	docker tag "rotisserie-sp:$$(cat $(REV_FILE))" "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-sp:$$(cat $(REV_FILE))"

# Uploads images to IBM Cointainer Repository. Runs set-rev to ensure that the rev_file exists.
upload-images: set-rev
	docker push "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-app:$$(cat $(REV_FILE))"
	docker push "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-ocr:$$(cat $(REV_FILE))"
	docker push "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-static:$$(cat $(REV_FILE))"
	docker push "registry.ng.bluemix.net/$(IMAGE_NAMESPACE)/rotisserie-sp:$$(cat $(REV_FILE))"

# Runs all image related tasks.
all-images: set-rev images tag-images upload-images

## Kubernetes ##

# Creates secrets required for the cluster based on the rotisserie-secrets.yaml file.
secrets:
	kubectl create -f rotisserie-secrets.yaml || true

# Deploys based on the rotisserie.yaml file. Runs set-rev to ensure that the rev_file exists. Uses revision
# to set the image_tag in rotisserie.yaml.
.PHONY: deploy
deploy: set-rev
	IMAGE_TAG=$$(cat $(REV_FILE)) envsubst < deploy/rotisserie.yaml | kubectl apply -n rotisserie -f -

# Deploys kube-lego based on the letsencrypt.yaml and kube-lego.yaml files.
kube-lego:
	kubectl create -f letsencrypt.yaml
	kubectl create -f deploy/kube-lego.yaml

# Deletes the app, ocr, and static deployments using kubectl delete.
delete-deployments:
	kubectl delete deploy rotisserie-app
	kubectl delete deploy rotisserie-ocr
	kubectl delete deploy rotisserie-static

# Runs delete-deployments then runs deploy.
redeploy: delete-deployments deploy

# Creates a new deployment from scratch, without kube-lego.
roll: all-images secrets deploy

# Creates a new deployment from scratch, with kube-lego.
full-roll: roll kube-lego

# Deletes deployments based on deployment files.
purge:
	kubectl delete -f deploy/rotisserie.yaml || true
	kubectl delete -f deploy/kube-lego.yaml || true
	kubectl delete -f rotisserie-secrets.yaml || true
	kubectl delete -f letsencrypt.yaml || true
	kubectl delete ing kube-lego-nginx || true
	kubectl delete secrets kube-lego-account || true
	kubectl delete secrets rotisserie-tls || true
