# PostgreSQL sul cluster Gandalf

Questo progetto installa PostgreSQL con il chart Helm di Bitnami nel namespace dedicato `postgresql`, come servizio condiviso per le applicazioni del cluster. Il Service `postgresql` è interno al cluster su `postgresql.postgresql.svc.cluster.local:5432` ed è esposto anche tramite `LoadBalancer` MetalLB sulla porta `5432`.

Per sicurezza, il Service accetta connessioni solo dalla LAN Gandalf (`10.89.1.0/24`) per impostazione predefinita. Non è esposto liberamente a Internet. Per consentire altre reti, impostare `POSTGRESQL_ALLOWED_CIDRS` con una o più reti CIDR separate da virgola; MetalLB assegna l'IP automaticamente, oppure si può scegliere un IP libero del pool `10.89.1.30-10.89.1.40` tramite `POSTGRESQL_LB_IP`.

All'installazione vengono creati un database e un utente applicativo, configurabili tramite variabili d'ambiente. Per impostazione predefinita entrambi si chiamano `application`. Il PVC persistente usa la StorageClass predefinita del cluster e richiede 30 GiB.

PostgreSQL richiede per impostazione predefinita `1Gi` di memoria e può usare fino a `2Gi` durante operazioni intense come l'inizializzazione dello schema Zabbix. Modificare `postgresql_memory_request` e `postgresql_memory_limit` in `group_vars/all.yml` per adattare questi valori.

## Prerequisiti

- Ansible installato sul controller.
- Helm 3 installato sul controller.
- Kubeconfig già configurato per Gandalf, predefinito `~/.kube/config`. Per un percorso diverso impostare `K8S_KUBECONFIG`.
- Una StorageClass predefinita funzionante e spazio sufficiente per il PVC.
- La collection `kubernetes.core` e le dipendenze Python installate.

Su AlmaLinux/RHEL, installare le dipendenze nel virtualenv Ansible:

```sh
sudo dnf install python3-pip
python3 -m venv ~/.venvs/ansible
source ~/.venvs/ansible/bin/activate
python -m pip install ansible
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

Installare Helm 3 seguendo la [guida ufficiale](https://helm.sh/docs/intro/install/).

## Installazione

Impostare `POSTGRESQL_PASSWORD` nell'ambiente senza salvarla nella history. È consigliata una password robusta di almeno 16 caratteri:

```sh
read -rsp 'Password PostgreSQL: ' POSTGRESQL_PASSWORD; printf '\n'; export POSTGRESQL_PASSWORD
```

Facoltativamente, cambiare database e utente iniziali o dimensione del volume prima dell'installazione:

```sh
export POSTGRESQL_DATABASE=application
export POSTGRESQL_USER=application
export POSTGRESQL_STORAGE_SIZE=30Gi
export POSTGRESQL_LB_IP=10.89.1.31
export POSTGRESQL_ALLOWED_CIDRS=10.89.1.0/24
```

Le ultime due variabili sono facoltative: omettere `POSTGRESQL_LB_IP` per l'assegnazione automatica e `POSTGRESQL_ALLOWED_CIDRS` per mantenere l'accesso limitato alla LAN Gandalf.

Dalla cartella `k8s-gandalf-postgresql` installare PostgreSQL:

```sh
ansible-playbook playbooks/install-postgresql.yml
```

Il chart Bitnami è fissato alla versione `18.12.4`, con PostgreSQL `18.6.0`; per cambiare versione chart modificare `postgresql_chart_version` in `group_vars/all.yml`. Il playbook prepara un database e un utente iniziali; per altre applicazioni creare database e ruoli aggiuntivi in PostgreSQL e assegnare loro credenziali dedicate.

La password viene passata in modo protetto ad Ansible ma Helm la conserva nelle proprie release e nel Secret PostgreSQL. Proteggere l'accesso al cluster e non cambiare la password nei valori Helm senza aggiornare anche la password effettiva nel database.

## Verifica

```sh
kubectl -n postgresql get pods,pvc,service
kubectl -n postgresql get service postgresql
```

Il PVC deve risultare `Bound` e il pod `Ready`. Il campo `EXTERNAL-IP` del Service è l'indirizzo da usare dai client esterni al cluster; connettersi alla porta `5432` usando il database, l'utente e la password configurati.

## Rimozione

Disinstallare PostgreSQL solo dopo aver fermato le applicazioni che lo utilizzano e salvato i dati:

```sh
helm uninstall postgresql --namespace postgresql
```

La rimozione della release non sostituisce un backup. Verificare lo stato e la retention del PVC prima di cancellare namespace o volumi.