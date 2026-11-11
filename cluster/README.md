# Cluster Kubernetes gandlaf su Hyper-V

Lo script PowerShell `create_vms.ps1` crea le tre VM Hyper-V per l'installazione manuale di CentOS Stream 10. Il playbook Ansible configura poi il cluster Kubernetes con kubeadm, Flannel e MetalLB per i servizi `LoadBalancer`.

## Parametri previsti

| Nodo | IP | vCPU | RAM |
| --- | --- | ---: | ---: |
| gandlaf-master1 | 10.89.1.20/24 | 4 | 8 GB |
| gandlaf-worker1 | 10.89.1.25/24 | 4 | 16 GB |
| gandlaf-worker2 | 10.89.1.26/24 | 4 | 16 GB |

Gateway e DNS: `10.89.1.1`. Lo script crea lo switch Hyper-V esterno `K8s-External` se non esiste.

MetalLB usa il pool `10.89.1.30-10.89.1.40` e annuncia gli IP sulla LAN con Layer 2. Riservare questo intervallo fuori dal DHCP e verificare che nessun altro dispositivo lo usi; il valore si modifica con `metallb_ip_range` in `group_vars/all.yml`.

## Prerequisiti

- Windows con Hyper-V e PowerShell amministrativo per eseguire `create_vms.ps1`.
- Controller Linux/WSL con Ansible, accesso SSH ai nodi e `sshpass` se si usa autenticazione SSH a password.
- Sul controller AlmaLinux/RHEL installare `pip` dai pacchetti di sistema e creare un ambiente virtuale per Ansible:

  ```sh
  sudo dnf install python3-pip
  python3 -m venv ~/.venvs/ansible
  source ~/.venvs/ansible/bin/activate
  python -m pip install ansible
  ansible-galaxy collection install -r requirements.yml
  ```

  In ogni nuova shell, riattivare l'ambiente con `source ~/.venvs/ansible/bin/activate`.

## Creazione e installazione delle VM

Sul server Windows con Hyper-V, aprire `create_vms.ps1` e verificare i percorsi `$ISO` e `$VMRoot`. Eseguire PowerShell come amministratore, spostarsi nella cartella dello script e avviarlo:

```powershell
.\create_vms.ps1
```

Eseguire lo script una sola volta per creare le VM. Completare l'installazione da console Hyper-V. Configurare gli IP statici indicati sopra, hostname `gandlaf-master1`, `gandlaf-worker1`, `gandlaf-worker2`, gateway/DNS `10.89.1.1`, SSH e un utente con privilegi sudo. Sul controller impostare `K8S_USER` all'utente creato; è possibile autenticarsi via chiave o password.

## Configurazione del cluster

Impostare `K8S_USER`. Per usare la password SSH dei nodi, inserirla nell'ambiente senza salvarla nella history della shell:

```sh
read -rsp 'Password SSH nodi: ' K8S_PASSWORD; printf '\n'; export K8S_PASSWORD
```

La stessa password viene usata anche per `sudo`. Se quella di `sudo` è diversa, impostare anche `K8S_BECOME_PASSWORD` con lo stesso metodo. Con autenticazione SSH a password via OpenSSH è necessario avere `sshpass` installato sul controller. In alternativa, usare la chiave `~/.ssh/id_ed25519` oppure impostare `K8S_SSH_KEY` al percorso della chiave.

Prima della prima connessione, aggiungere le chiavi host SSH al controller. Da ciascuna console VM verificare la fingerprint con:

```sh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Sul controller, confrontare le fingerprint ricevute con quelle mostrate dalle console, poi registrare le chiavi:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
for ip in 10.89.1.20 10.89.1.25 10.89.1.26; do
  printf '%s: ' "$ip"
  ssh-keyscan -t ed25519 "$ip" 2>/dev/null | ssh-keygen -lf /dev/stdin
done
ssh-keyscan -H -t ed25519 10.89.1.20 10.89.1.25 10.89.1.26 >> ~/.ssh/known_hosts
```

`ssh-keyscan` da solo non autentica il server: procedere solo se le fingerprint corrispondono a quelle verificate sulle VM.

Poi eseguire:

```sh




```

Il playbook configura containerd, kubelet/kubeadm/kubectl (repository Kubernetes `v1.35`), inizializza il control plane, installa Flannel e MetalLB e unisce i worker. Aggiunge le interfacce CNI `cni0` e `flannel.1` alla zona `trusted` di firewalld e consente il traffico kubeadm, Flannel, MetalLB memberlist e NodePort. Il kubeconfig amministrativo viene installato in `~/.kube/config` sull'utente dei nodi.

Per assegnare un IP MetalLB, crea un Service Kubernetes con `spec.type: LoadBalancer`; l'indirizzo assegnato sarà nel pool e raggiungibile dalla LAN. Verifica con `kubectl get services`.

### Errore preflight di kubeadm

Se `kubeadm` rileva meno di 1,7 GiB sul master, spegni CentOS correttamente (`sudo poweroff`) e da PowerShell amministrativo sull'host Hyper-V controlla e imposta la RAM statica:

```powershell
Get-VMMemory -VMName gandlaf-master1
Set-VMMemory -VMName gandlaf-master1 -DynamicMemoryEnabled $false -StartupBytes 8GB
```

Avvia nuovamente la VM da Hyper-V e verifica nel guest con `free -h` che siano visibili circa 8 GiB. Per i worker usa `-StartupBytes 16GB`. Il playbook ora controlla la RAM rilevata prima di procedere e abilita il plugin CRI anche se `config.toml` esisteva già; dopo aver sistemato RAM e containerd, rieseguilo.

## Note

- Gli IP `.20`, `.25` e `.26` sono stati assegnati nell'ordine master, worker1, worker2; cambiarli in `group_vars/all.yml` e `inventories/hosts.yml` se non sono quelli desiderati.
- La versione Kubernetes si cambia in `group_vars/all.yml`. Verificare la disponibilità della minor version scelta nel repository pkgs.k8s.io prima dell'installazione.