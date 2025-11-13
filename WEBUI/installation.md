Si vous n'êtes pas famillier avec Python, voici un petit cheatsheet pour vous permettre d'utiliser facilement l'interface graphique réalisée :

#### Sur la VM, dans l'environnement RAG
```
cd ~
source rag_env/bin/activate
```
#### Installer Flask et Socket.IO
```
pip install flask flask-socketio
```
#### Sauvegarder le script 
```
nano rag_webui.py
(coller le code)

chmod +x rag_webui.py
```
#### Lancer
```
python rag_webui.py
```

### Accès

Depuis la VM :
```
http://localhost:5000
```

Depuis le Mac (si VM accessible) :
```
http://172.16.74.141:5000
```

### Configuration pare-feu VM (si nécessaire) :
```
sudo firewall-cmd --add-port=5000/tcp --permanent
sudo firewall-cmd --reload
