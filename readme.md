<div align="center">

# 📚 FAMILY RAG

### *La mémoire vivante de votre famille*

*Interrogez en langage naturel l'histoire, les recettes, les documents administratifs et les cours de votre famille accessible par l'IA et surtout SANS CONNEXION INTERNET !*


[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.14+-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Flask](https://img.shields.io/badge/Flask-3.0+-000000?logo=flask&logoColor=white)](https://flask.palletsprojects.com/)
[![Ollama](https://img.shields.io/badge/Ollama-Latest-FF6B6B)](https://ollama.ai/)
[![Langchain](https://img.shields.io/badge/🦜_Langchain-Latest-00A67E)](https://langchain.com/)
[![FAISS](https://img.shields.io/badge/FAISS-GPU-4285F4?logo=meta&logoColor=white)](https://github.com/facebookresearch/faiss)
[![Fedora](https://img.shields.io/badge/Fedora-43-51A2DA?logo=fedora&logoColor=white)](https://getfedora.org/)
[![macOS](https://img.shields.io/badge/macOS-Compatible-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)

</div>

---

## 🎯 Pourquoi Family RAG ?

Chaque famille accumule au fil des années une **richesse documentaire** considérable :


- 📜 **Documents administratifs** : actes, contrats, factures, garanties
- 👨‍👩‍👧‍👦 **Histoire familiale** : lettres, biographies, photos légendées, arbres généalogiques
- 🍳 **Savoir-faire** : recettes de grand-mère, techniques artisanales, tours de main
- 📚 **Éducation** : cours des enfants, notes de révision, fiches méthodes
- 🏡 **Patrimoine** : plans, diagnostics, travaux, entretien maison



Aujourd'hui je propose un système facilement déployable, **intelligent et privé** qui :

- ✅ **Centralise** tous vos documents en un seul endroit
- ✅ **Comprend** le sens de vos questions en langage naturel
- ✅ **Répond** en s'appuyant sur vos propres archives
- ✅ **Préserve** la mémoire familiale vectorisée pour les générations futures
- ✅ **Reste local** : aucune donnée ne quitte votre infrastructure



### Voici quelques cas d'usage concrets

**📋 Administratif**
> *"Où est la garantie du lave-vaisselle acheté en 2019 ?"*
> 
> *"Quelle est la date d'échéance de l'assurance habitation ?"*

**👴 Histoire familiale**
> *"Raconte-moi l'histoire de l'arrière-grand-père pendant la guerre"*
> 
> *"Quand la maison familiale a-t-elle été construite ?"*

**🍲 Cuisine & savoir-faire**
> *"Comment grand-mère faisait-elle son bœuf bourguignon ?"*
> 
> *"Quelle est la technique pour bouturer les rosiers ?"*

**📖 Éducation enfants**
> *"Explique-moi la règle des participes passés vue en CM2"*
> 
> *"Résume le cours de SVT sur la photosynthèse"*

### Stack technologique

<div align="center">

| Composant | Technologie | Rôle |
|-----------|-------------|------|
| 🖥️ **Hôte** | macOS (M3 Pro) | Hébergement Ollama & documents |
| 🤖 **LLM** | Mistral 7B | Génération réponses |
| 🧠 **Embeddings** | Nomic Embed Text | Vectorisation sémantique |
| 🐧 **VM** | Fedora 43 | Traitement & indexation |
| 🐍 **Framework** | Langchain + FAISS | Pipeline RAG |
| 🌐 **Interface** | Flask + Socket.IO | WebUI temps réel |
| 🔗 **Partage** | SSHFS | Montage documents |
| 📦 **Formats** | 8 types | PDF, DOCX, TXT, MD, ODT, HTML, EPUB, EML |

</div>

### Flux de données
```mermaid
graph LR
    A[📄 Documents] -->|SSHFS| B[VM: Parse]
    B -->|Chunks| C[FAISS]
    C -->|Embeddings| D[Mac: Ollama]
    E[👤 Question] -->|WebUI| F[Recherche]
    F -->|Contexte| D
    D -->|Réponse| E
```

---

## ⚡ Installation en 2 scripts

# Machine hôte (IA + modèles)
./setup-macos.sh

# Machine virtuelle (RAG)
./setup-rag-vm.sh

Accès à la webUI : http://<VM_IP>:5000

## 🧹 Désinstallation

# Machine hôte
./cleanup-macos.sh

# Machine virtuelle
./cleanup-vm.


## 🛡️ Sécurité & Confidentialité

- ✅ **100% local** : Aucune donnée ne sort de votre infrastructure
- ✅ **Offline-ready** : Fonctionne sans Internet APRÈS installation
- ✅ **Réseau privé** : Communication Mac ↔ VM isolée
- ✅ **Pas de cloud** : Vos archives familiales restent privées
- ✅ **Open source** : Code auditable et modifiable

---

## 🗺️ Roadmap

- [ ] Interropérabilité Windows
- [ ] Prise en charge des formats JPEG, PNG, MP3, MP4
- [ ] Export PDF des conversations
- [ ] Au fil de l'eau..

---

## 🤝 Contribution

Les contributions sont les bienvenues ! Ce projet est né d'un **besoin personnel** de transmission intergénérationnelle et d'efficacité quotidienne.

- 🐛 **Bugs** : [Ouvrir une issue](https://github.com/liam4chilll/FAMILY_RAG/issues)
- 🔧 **Code** : Fork → Branch → PR

[Lire la licence complète →](LICENSE)

</div>

---

J'ai conçu Family RAG avec des technologies open-source :

<div align="center">

[![Ollama](https://img.shields.io/badge/Ollama-FF6B6B?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAEGSURBVCiRY2AYBaNgFAwQYPj//z8DAwPDfwYGhv8MDAwMjIyMDP///2dgYGBg+P//PwMDA8N/BgYGhv///zMwMDAwMDAwMPz//58BRQADR0AQGQwMDAwMDAwM/xkYGP4zMDAwMDAwMPxnYGBgYGBgYGBgYGBgYGBg+M/AwMDAwMDA8J+BgYGBgYHhPwMDAwMDAwPDfwYGBgYGBgaG/wwMDAwMDAwM/xkYGBgYGBgY/jMwMDAwMDAw/GdgYGBgYGBg+M/AwMDAwMDA8J+BgYGBgYGB4T8DAwMDAwMDw38GBgYGBgYGhv8MDAwMDAwMDP8ZGBgYGBgYGP4zMDAwMDAw/GdgYGBgYGBg+M/AwMDAwMDwHwBZNhcQ6YEpVwAAAABJRU5ErkJggg==)](https://ollama.ai/)
[![Langchain](https://img.shields.io/badge/🦜_Langchain-00A67E?style=for-the-badge)](https://langchain.com/)
[![FAISS](https://img.shields.io/badge/FAISS-4285F4?style=for-the-badge&logo=meta&logoColor=white)](https://github.com/facebookresearch/faiss)
[![Flask](https://img.shields.io/badge/Flask-000000?style=for-the-badge&logo=flask&logoColor=white)](https://flask.palletsprojects.com/)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)

</div>

Merci à la communauté open-source qui rend ce type de projet possible !

 Si ce projet résonne avec vous, donnez-lui une étoile ⭐ !

**Family RAG est fait avec ❤️ pour préserver et transmettre la mémoire familiale de chacun**

[⬆ Retour en haut](#-FAMILY_RAG)
