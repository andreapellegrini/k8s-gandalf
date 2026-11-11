# Jenkins sul cluster Gandalf

Questo progetto configura uno storage NFS su una VM dedicata e installa Jenkins con il chart Helm ufficiale nel namespace `jenkins`. Il playbook prepara anche i client NFS sui nodi, il driver CSI NFS e una `StorageClass` persistente.

Il servizio viene pubblicato come `LoadBalancer`, così MetalLB può assegnargli un IP del pool del cluster. La persistenza è attiva: serve una `StorageClass` predefinita funzionante nel cluster, altrimenti il PVC di Jenkins rimane `Pending` e il pod non parte.

## VM storage Hyper-V

Lo script [create_nfs_storage_vm.ps1](create_nfs_storage_vm.ps1) crea la VM `gandalf-storage1` con CentOS, un disco OS da 40 GB e un disco dati dedicato da 100 GB. Il disco dati resta collegato solo a questa VM; NFS lo espone ai nodi Kubernetes senza condividere un VHDX grezzo. La VM storage è un singolo punto di guasto: questa configurazione non replica i dati né fornisce HA.

```powershell
.\create_nfs_storage_vm.ps1 -WhatIf
.\create_nfs_storage_vm.ps1
```

Lo script usa l'ISO CentOS e lo switch `K8s-External` già previsti nel progetto Gandalf; se i percorsi differiscono, passarli con `-ISO`, `-VMRoot` e `-SwitchName`. Dopo l'installazione manuale di CentOS, configura hostname `gandalf-storage1`, IP statico `10.89.1.15/24`, gateway/DNS `10.89.1.1`, SSH e lo stesso utente amministrativo usato sui nodi. Verifica che `.15` sia libero e riservato.

Il nome del disco aggiuntivo può essere `/dev/sda`, `/dev/sdb` o altro: prima di continuare individua il disco dati con `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS` e distinguilo dal disco OS, che contiene `/` e `/boot`. Il playbook non formatta un disco vuoto senza l'opzione esplicita `-e nfs_format_data_disk=true`; se è già XFS e montato su `/srv/nfs`, lo riutilizza senza riformattarlo.

## Prerequisiti

- Ansible installato sul controller.
- Helm 3 installato sul controller.
- `kubectl` configurato per il cluster Gandalf; il kubeconfig predefinito è `~/.kube/config`. Per un percorso diverso impostare `K8S_KUBECONFIG`.
- Accesso SSH ai tre nodi Kubernetes e alla VM `gandalf-storage1`.
- Un IP statico raggiungibile per il server NFS; l'indirizzo predefinito è `10.89.1.15` e si cambia con `NFS_SERVER_IP`.
- Spazio sufficiente sul disco dati NFS per il PVC Jenkins.

Su AlmaLinux/RHEL, creare e attivare un ambiente virtuale Ansible (se non ne esiste già uno), quindi installare Ansible e le dipendenze Python:

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

Dopo aver installato CentOS sulla VM storage, configura le variabili SSH usate anche dal progetto Gandalf. Per autenticazione a password, inseriscila senza salvarla nella history:

```sh
export K8S_USER=nome_utente
export NFS_SERVER_IP=10.89.1.15
read -rsp 'Password SSH nodi: ' K8S_PASSWORD; printf '\n'; export K8S_PASSWORD
```

Se la password sudo è diversa, impostare anche `K8S_BECOME_PASSWORD`; per autenticazione a chiave impostare `K8S_SSH_KEY` se non si usa `~/.ssh/id_ed25519`. Attivare il virtualenv Ansible, quindi dalla cartella `k8s-gandalf-jenkins` installare collection e dipendenze:

```sh
ansible-galaxy collection install -r requirements.yml
python -m pip install -r requirements.txt
```

Eseguire il playbook indicando esplicitamente il disco dati da inizializzare la prima volta:

```sh
ansible-playbook playbooks/install-jenkins.yml \
	-e nfs_data_device=/dev/sda \\
	-e nfs_format_data_disk=true
```

Il playbook verifica che il device sia un disco intero non montato e formatta solo se è vuoto. Se è già XFS, omettere `nfs_format_data_disk=true`. Configura NFSv4 limitato ai tre nodi Gandalf, installa il CSI NFS e crea `nfs-jenkins` con `Retain`; Jenkins mantiene i dati nel namespace dedicato. La classe viene impostata come predefinita a livello cluster per consentire l'assegnazione anche al PVC Pending già creato: i nuovi PVC senza classe negli altri namespace useranno anch'essi NFS.

Per fissare una versione specifica del chart Jenkins, passare `jenkins_chart_version`, ad esempio `-e jenkins_chart_version=5.8.110`. Il CSI NFS usa la versione `4.13.5`, configurabile con `nfs_csi_chart_version`.

## Verifica e accesso

Controllare che pod, PVC e servizio siano pronti:

```sh
kubectl -n jenkins get pods,pvc,service
kubectl get storageclass
```

Se il PVC resta `Pending`, controllare gli eventi con `kubectl -n jenkins describe pvc jenkins` e verificare che `nfs-jenkins` sia la classe assegnata. Non eliminare un PVC `Bound` senza prima salvare i dati.

Recuperare l'IP assegnato da MetalLB con `kubectl -n jenkins get service jenkins` e aprire `http://<IP>`. Per consultare la password iniziale dell'utente `admin`:

```sh
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo
```

Per rimuovere Jenkins mantenendo il namespace e gli eventuali dati persistenti:

```sh
helm uninstall jenkins --namespace jenkins
```