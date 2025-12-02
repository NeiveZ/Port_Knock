# Port_Knock

Este é um script robusto em **Bash** desenvolvido para fins de auditoria de segurança de rede e detecção de serviços ocultos ativados pela técnica de **Port Knocking**.

O script permite que administradores de rede e profissionais de segurança (Red/Blue Team) varram uma sub-rede específica. Para cada host ativo, ele executa uma sequência de conexões (o "knock") em portas predefinidas e, em seguida, verifica se uma porta alvo (padrão 1337) foi aberta como resultado, indicando um serviço que usa Port Knocking para acesso.

## Requisitos

Para garantir a funcionalidade ideal, recomenda-se a instalação das seguintes ferramentas:

* **Bash:** Interpretador de comandos (nativo na maioria dos sistemas Linux e macOS).
* **nmap:** Utilizado para a verificação confiável da porta alvo. Se não estiver instalado, o script fará um fallback para a verificação nativa do Bash (`/dev/tcp`).
* **timeout:** Usado para garantir que as conexões não fiquem travadas (geralmente parte do pacote `coreutils`).
