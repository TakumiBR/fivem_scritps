// NRP Character Creation UI - JavaScript

let nationalities = [];

// Elementos DOM
const app = document.getElementById('app');
const creationForm = document.getElementById('creationForm');
const firstnameInput = document.getElementById('firstname');
const lastnameInput = document.getElementById('lastname');
const dobDaySelect = document.getElementById('dobDay');
const dobMonthSelect = document.getElementById('dobMonth');
const dobYearSelect = document.getElementById('dobYear');
const nationalitySelect = document.getElementById('nationality');
const btnContinue = document.getElementById('btnContinue');

// Listener para mensagens do FiveM
window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'openCreation') {
        openCreation(data.config);
    } else if (data.action === 'closeNUI') {
        closeNUI();
    }
});

// Abrir tela de criação
function openCreation(config) {
    app.classList.remove('hidden');
    
    // Preencher nacionalidades
    if (config && config.nationalities) {
        nationalities = config.nationalities;
        populateNationalities();
    }
    
    // Popular selects de data
    populateDateSelects();
    
    // Limpar formulário
    creationForm.reset();
    clearErrors();
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

// Popular select de nacionalidades
function populateNationalities() {
    nationalitySelect.innerHTML = '<option value="">Selecione...</option>';
    
    nationalities.forEach(nat => {
        const option = document.createElement('option');
        option.value = nat;
        option.textContent = nat;
        nationalitySelect.appendChild(option);
    });
}

// Popular selects de data
function populateDateSelects() {
    // Dias (1-31)
    for (let i = 1; i <= 31; i++) {
        const option = document.createElement('option');
        option.value = i;
        option.textContent = i.toString().padStart(2, '0');
        dobDaySelect.appendChild(option);
    }
    
    // Meses
    const months = [
        'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
        'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    
    months.forEach((month, index) => {
        const option = document.createElement('option');
        option.value = index + 1;
        option.textContent = month;
        dobMonthSelect.appendChild(option);
    });
    
    // Anos (18 a 100 anos atrás)
    const currentYear = new Date().getFullYear();
    const minYear = currentYear - 100;
    const maxYear = currentYear - 18;
    
    for (let i = maxYear; i >= minYear; i--) {
        const option = document.createElement('option');
        option.value = i;
        option.textContent = i;
        dobYearSelect.appendChild(option);
    }
}

// Validar nome
function validateName(name, isLastName) {
    const maxLength = isLastName ? 20 : 15;
    const minLength = 3;
    
    if (!name || name.trim().length < minLength) {
        return { valid: false, error: 'Nome muito curto (mínimo 3 caracteres)' };
    }
    
    if (name.trim().length > maxLength) {
        return { valid: false, error: `Nome muito longo (máximo ${maxLength} caracteres)` };
    }
    
    // Permitir apenas letras, espaços e apóstrofe (para sobrenomes)
    const pattern = isLastName ? /^[\p{L}\s']+$/u : /^[\p{L}\s]+$/u;
    
    if (!pattern.test(name.trim())) {
        return { valid: false, error: 'Nome contém caracteres inválidos (apenas letras, espaços e apóstrofe)' };
    }
    
    return { valid: true, error: null };
}

// Mostrar erro
function showError(fieldId, message) {
    const errorEl = document.getElementById(fieldId + 'Error');
    if (errorEl) {
        errorEl.textContent = message;
    }
}

// Limpar erros
function clearErrors() {
    document.querySelectorAll('.error-message').forEach(el => {
        el.textContent = '';
    });
}

// Submissão do formulário
creationForm.addEventListener('submit', function(e) {
    e.preventDefault();
    
    clearErrors();
    
    // Obter valores
    const firstname = firstnameInput.value.trim();
    const lastname = lastnameInput.value.trim();
    const day = dobDaySelect.value;
    const month = dobMonthSelect.value;
    const year = dobYearSelect.value;
    const nationality = nationalitySelect.value;
    const gender = document.querySelector('input[name="gender"]:checked');
    
    let hasError = false;
    
    // Validar primeiro nome
    const firstnameValidation = validateName(firstname, false);
    if (!firstnameValidation.valid) {
        showError('firstname', firstnameValidation.error);
        hasError = true;
    }
    
    // Validar sobrenome
    const lastnameValidation = validateName(lastname, true);
    if (!lastnameValidation.valid) {
        showError('lastname', lastnameValidation.error);
        hasError = true;
    }
    
    // Validar data de nascimento
    if (!day || !month || !year) {
        showError('dob', 'Selecione uma data completa');
        hasError = true;
    }
    
    // Validar nacionalidade
    if (!nationality) {
        showError('nationality', 'Selecione uma nacionalidade');
        hasError = true;
    }
    
    // Validar gênero
    if (!gender) {
        showError('gender', 'Selecione um gênero');
        hasError = true;
    }
    
    if (hasError) {
        return;
    }
    
    // Montar dados do personagem
    const characterData = {
        firstname: firstname,
        lastname: lastname,
        dob: `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`,
        nationalid: nationality,
        gender: gender.value
    };
    
    // Enviar para o servidor
    fetch(`https://${GetParentResourceName()}/createCharacter`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(characterData)
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            // Sucesso - abrir tela de appearance ou entrar no jogo
            fetch(`https://${GetParentResourceName()}/finishCreation`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({})
            });
        } else {
            // Erro na criação
            alert('Erro ao criar personagem: ' + data.message);
        }
    })
    .catch(error => {
        console.error('Erro:', error);
        alert('Erro ao comunicar com o servidor');
    });
});

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
