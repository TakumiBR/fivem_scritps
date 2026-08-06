// NRP Multicharacter UI - JavaScript

let characters = [];
let selectedCharacter = null;
let maxCharacters = 5;

// Elementos DOM
const app = document.getElementById('app');
const serverNameEl = document.getElementById('serverName');
const charactersGrid = document.getElementById('charactersGrid');
const characterInfoPanel = document.getElementById('characterInfoPanel');
const btnCreate = document.getElementById('btnCreate');
const btnPlay = document.getElementById('btnPlay');
const btnCancel = document.getElementById('btnCancel');
const btnDelete = document.getElementById('btnDelete');

// Elementos de informação do personagem
const charNameEl = document.getElementById('charName');
const charFullNameEl = document.getElementById('charFullName');
const charGenderEl = document.getElementById('charGender');
const charDobEl = document.getElementById('charDob');
const charNationalityEl = document.getElementById('charNationality');
const charMoneyEl = document.getElementById('charMoney');
const charJobEl = document.getElementById('charJob');

// Listener para mensagens do FiveM
window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'openMultichar') {
        openMultichar(data.config);
    } else if (data.action === 'closeNUI') {
        closeNUI();
    } else if (data.action === 'updateCharacters') {
        updateCharactersList(data.characters);
    }
});

// Abrir tela de multicharacter
function openMultichar(config) {
    app.classList.remove('hidden');
    
    if (config && config.serverName) {
        serverNameEl.textContent = config.serverName.toUpperCase();
    }
    
    if (config && config.maxCharacters) {
        maxCharacters = config.maxCharacters;
    }
    
    // Carregar lista de personagens
    loadCharacters();
}

// Fechar NUI
function closeNUI() {
    app.classList.add('hidden');
    fetch(`https://${GetParentResourceName()}/closeNUI`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });
}

// Carregar personagens do servidor
function loadCharacters() {
    fetch(`https://${GetParentResourceName()}/getCharacters`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    })
    .then(response => response.json())
    .then(data => {
        characters = data || [];
        renderCharactersGrid();
    })
    .catch(error => {
        console.error('Erro ao carregar personagens:', error);
        characters = [];
        renderCharactersGrid();
    });
}

// Renderizar grid de personagens
function renderCharactersGrid() {
    charactersGrid.innerHTML = '';
    
    // Renderizar slots com personagens existentes
    characters.forEach((char, index) => {
        const slot = createCharacterSlot(char, index);
        charactersGrid.appendChild(slot);
    });
    
    // Renderizar slots vazios até o máximo
    const emptySlotsCount = maxCharacters - characters.length;
    for (let i = 0; i < emptySlotsCount; i++) {
        const slot = createEmptySlot(characters.length + i);
        charactersGrid.appendChild(slot);
    }
    
    // Mostrar botão de criar se houver slots vazios
    btnCreate.style.display = characters.length < maxCharacters ? 'inline-flex' : 'none';
}

// Criar slot com personagem
function createCharacterSlot(char, index) {
    const slot = document.createElement('div');
    slot.className = 'character-slot has-character';
    slot.dataset.index = index;
    
    slot.innerHTML = `
        <i class="fas fa-user slot-icon"></i>
        <span class="slot-label">${char.firstname} ${char.lastname}</span>
    `;
    
    slot.addEventListener('click', () => selectCharacter(char, slot));
    
    return slot;
}

// Criar slot vazio
function createEmptySlot(index) {
    const slot = document.createElement('div');
    slot.className = 'character-slot';
    slot.dataset.index = index;
    
    slot.innerHTML = `
        <i class="fas fa-plus-circle slot-icon"></i>
        <span class="slot-label">Personagem ${index + 1}</span>
    `;
    
    slot.addEventListener('click', () => {
        // Se clicar em slot vazio, criar novo personagem
        createNewCharacter();
    });
    
    return slot;
}

// Selecionar personagem
function selectCharacter(char, slotElement) {
    // Remover seleção anterior
    document.querySelectorAll('.character-slot').forEach(s => s.classList.remove('selected'));
    
    // Adicionar seleção atual
    slotElement.classList.add('selected');
    selectedCharacter = char;
    
    // Preencher informações
    charNameEl.textContent = `${char.firstname} ${char.lastname}`;
    charFullNameEl.textContent = `${char.firstname} ${char.lastname}`;
    charGenderEl.textContent = char.gender === 'm' ? 'Masculino' : 'Feminino';
    charDobEl.textContent = formatDate(char.dob);
    charNationalityEl.textContent = char.nationalid || 'Não informado';
    charMoneyEl.textContent = formatMoney(char.cash || 0);
    charJobEl.textContent = char.job ? char.job.label : 'Desempregado';
    
    // Mostrar painel de informações
    characterInfoPanel.classList.remove('hidden');
}

// Criar novo personagem
function createNewCharacter() {
    fetch(`https://${GetParentResourceName()}/createNewCharacter`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });
    closeNUI();
}

// Deletar personagem
btnDelete.addEventListener('click', () => {
    if (!selectedCharacter) return;
    
    if (confirm(`Tem certeza que deseja deletar o personagem ${selectedCharacter.firstname} ${selectedCharacter.lastname}?`)) {
        fetch(`https://${GetParentResourceName()}/deleteCharacter`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                charId: selectedCharacter.id
            })
        });
        
        // Recarregar lista após deleção
        setTimeout(() => {
            loadCharacters();
            characterInfoPanel.classList.add('hidden');
            selectedCharacter = null;
        }, 500);
    }
});

// Botão Jogar
btnPlay.addEventListener('click', () => {
    if (!selectedCharacter) return;
    
    fetch(`https://${GetParentResourceName()}/selectCharacter`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            charId: selectedCharacter.id
        })
    });
    
    closeNUI();
});

// Botão Cancelar
btnCancel.addEventListener('click', () => {
    characterInfoPanel.classList.add('hidden');
    document.querySelectorAll('.character-slot').forEach(s => s.classList.remove('selected'));
    selectedCharacter = null;
});

// Botão Criar Novo Personagem
btnCreate.addEventListener('click', () => {
    createNewCharacter();
});

// Formatar data
function formatDate(dateString) {
    if (!dateString) return 'Não informado';
    
    const date = new Date(dateString);
    return date.toLocaleDateString('pt-BR');
}

// Formatat dinheiro
function formatMoney(amount) {
    return `R$ ${parseFloat(amount).toLocaleString('pt-BR', {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
}

// Tecla ESC para fechar
document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape' && !app.classList.contains('hidden')) {
        closeNUI();
    }
});

// Função auxiliar para obter nome do recurso
function GetParentResourceName() {
    return 'nrp-core';
}
