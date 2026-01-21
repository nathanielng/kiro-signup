// Toggle API key visibility
function toggleApiKeyVisibility() {
    const apiKeyInput = document.getElementById('api-key-input');
    const toggleIcon = document.getElementById('toggle-icon');
    
    if (apiKeyInput.type === 'password') {
        apiKeyInput.type = 'text';
        toggleIcon.textContent = '🙈';
    } else {
        apiKeyInput.type = 'password';
        toggleIcon.textContent = '👁️';
    }
}

// Get API key from input field
function getApiKey() {
    return document.getElementById('api-key-input').value.trim();
}

// Validate API key is provided
function validateApiKey() {
    const apiKey = getApiKey();
    if (!apiKey) {
        alert('Please enter your API key in the configuration section above.');
        document.getElementById('api-key-input').focus();
        return false;
    }
    return true;
}

// File upload preview
document.getElementById('screenshot-upload').addEventListener('change', function(e) {
    const file = e.target.files[0];
    if (file) {
        document.getElementById('file-name').textContent = file.name;
        
        // Show preview
        const reader = new FileReader();
        reader.onload = function(e) {
            document.getElementById('preview-img').src = e.target.result;
            document.getElementById('image-preview').style.display = 'block';
        };
        reader.readAsDataURL(file);
    }
});

// Check Credits Form
document.getElementById('check-credits-form').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    // Validate API key
    if (!validateApiKey()) {
        return;
    }
    
    const submitBtn = e.target.querySelector('button[type="submit"]');
    const btnText = submitBtn.querySelector('.btn-text');
    const btnLoader = submitBtn.querySelector('.btn-loader');
    const resultDiv = document.getElementById('check-credits-result');
    
    // Disable button and show loader
    submitBtn.disabled = true;
    btnText.style.display = 'none';
    btnLoader.style.display = 'inline';
    resultDiv.style.display = 'none';
    
    // Get form data
    const email = document.getElementById('credits-email').value;
    const firstName = document.getElementById('credits-firstname').value;
    const lastName = document.getElementById('credits-lastname').value;
    const fileInput = document.getElementById('screenshot-upload');
    const file = fileInput.files[0];
    
    if (!file) {
        resultDiv.className = 'result error';
        resultDiv.innerHTML = '<h3>❌ Error</h3><p>Please select a screenshot file</p>';
        resultDiv.style.display = 'block';
        submitBtn.disabled = false;
        btnText.style.display = 'inline';
        btnLoader.style.display = 'none';
        return;
    }
    
    try {
        // Read file as base64
        const base64Image = await fileToBase64(file);
        
        const payload = {
            image: base64Image,
            email: email,
            image_name: file.name
        };
        
        if (firstName) payload.firstName = firstName;
        if (lastName) payload.lastName = lastName;
        
        const response = await fetch(`${API_CONFIG.endpoint}/check-credits`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-api-key': getApiKey()
            },
            body: JSON.stringify(payload)
        });
        
        // Handle authentication errors
        if (response.status === 403) {
            resultDiv.className = 'result error';
            resultDiv.innerHTML = `
                <h3>❌ Authentication Failed</h3>
                <p>Invalid API key. Please check your API key and try again.</p>
                <p>You can retrieve your API key from AWS Systems Manager Parameter Store at:</p>
                <code>/kiro/kiro-user-management-api/api-key</code>
            `;
            resultDiv.style.display = 'block';
            submitBtn.disabled = false;
            btnText.style.display = 'inline';
            btnLoader.style.display = 'none';
            return;
        }
        
        // Handle rate limiting
        if (response.status === 429) {
            resultDiv.className = 'result error';
            resultDiv.innerHTML = `
                <h3>❌ Rate Limit Exceeded</h3>
                <p>Too many requests. Please wait a moment and try again.</p>
            `;
            resultDiv.style.display = 'block';
            submitBtn.disabled = false;
            btnText.style.display = 'inline';
            btnLoader.style.display = 'none';
            return;
        }
        
        const data = await response.json();
        
        if (response.ok) {
            // Handle different scenarios
            if (data.already_in_kiro_pro) {
                // User already has Kiro Pro access
                resultDiv.className = 'result success';
                resultDiv.innerHTML = `
                    <h3>✅ Already on Kiro Pro</h3>
                    <div class="result-details">
                        <p>You are already on the Kiro Pro plan. No action needed!</p>
                    </div>
                `;
            } else if (data.email_match === false) {
                // Email verification failed
                resultDiv.className = 'result error';
                resultDiv.innerHTML = `
                    <h3>❌ Email Verification Failed</h3>
                    <div class="result-details">
                        <p><strong>Email:</strong> ${data.email}</p>
                        <p>The email address in the screenshot does not match the email you provided. Please ensure you're submitting your own screenshot showing your account's credit usage.</p>
                    </div>
                `;
            } else if (data.credits_used_up === false) {
                // Credits still available
                resultDiv.className = 'result warning';
                resultDiv.innerHTML = `
                    <h3>⚠️ Credits Still Available</h3>
                    <div class="result-details">
                        <p><strong>Email:</strong> ${data.email}</p>
                        <p>Please use up your free Kiro credits before requesting Kiro Pro access.</p>
                    </div>
                `;
            } else if (data.credits_used_up && data.user_added_to_kiro_pro) {
                // Successfully upgraded to Kiro Pro
                resultDiv.className = 'result success';
                resultDiv.innerHTML = `
                    <h3>🎉 Welcome to Kiro Pro!</h3>
                    <div class="result-details">
                        <p><strong>Email:</strong> ${data.email}</p>
                        <p>Your screenshot has been logged and you've been successfully added to the Kiro Pro group.</p>
                        <p>It may take some time for your Kiro Pro access to be activated.</p>
                    </div>
                `;
            } else if (data.credits_used_up && !data.user_added_to_kiro_pro) {
                // Credits depleted but upgrade failed
                resultDiv.className = 'result warning';
                resultDiv.innerHTML = `
                    <h3>⚠️ Upgrade Failed</h3>
                    <div class="result-details">
                        <p><strong>Email:</strong> ${data.email}</p>
                        <p><strong>Issue:</strong> ${data.error || data.message}</p>
                        <p>Your credits are depleted, but we couldn't complete the upgrade. Please contact support.</p>
                    </div>
                `;
            } else {
                // Unexpected response
                resultDiv.className = 'result warning';
                resultDiv.innerHTML = `
                    <h3>ℹ️ Response Received</h3>
                    <div class="result-details">
                        <p>${data.message || 'Request processed'}</p>
                    </div>
                `;
            }
            
            // Reset form
            e.target.reset();
            document.getElementById('file-name').textContent = 'Choose a file or drag here';
            document.getElementById('image-preview').style.display = 'none';
        } else {
            // Handle other HTTP errors
            let errorMessage = 'Failed to check credits';
            
            if (response.status === 400) {
                errorMessage = data.message || 'Invalid request. Please check your input.';
            } else if (response.status === 500) {
                errorMessage = 'Server error. Please try again later.';
            } else if (data.message) {
                errorMessage = data.message;
            }
            
            resultDiv.className = 'result error';
            resultDiv.innerHTML = `
                <h3>❌ Error</h3>
                <p>${errorMessage}</p>
            `;
        }
    } catch (error) {
        // Handle network errors
        let errorMessage = 'Failed to process request';
        
        if (error.message === 'Failed to fetch') {
            errorMessage = 'Unable to connect to the API. Please check your internet connection and ensure the API endpoint is correct.';
        } else if (error.name === 'TypeError') {
            errorMessage = 'Network error. Please check your internet connection and try again.';
        } else {
            errorMessage = error.message;
        }
        
        resultDiv.className = 'result error';
        resultDiv.innerHTML = `
            <h3>❌ Connection Error</h3>
            <p>${errorMessage}</p>
        `;
    } finally {
        // Re-enable button and hide loader
        submitBtn.disabled = false;
        btnText.style.display = 'inline';
        btnLoader.style.display = 'none';
        resultDiv.style.display = 'block';
    }
});

// Helper function to convert file to base64
function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            // Remove the data URL prefix (e.g., "data:image/png;base64,")
            const base64 = reader.result.split(',')[1];
            resolve(base64);
        };
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}

// Check if API is configured
window.addEventListener('DOMContentLoaded', function() {
    // Load API key from sessionStorage if available
    const savedApiKey = sessionStorage.getItem('kiro_api_key');
    if (savedApiKey) {
        document.getElementById('api-key-input').value = savedApiKey;
    }
    
    // Save API key to sessionStorage when changed
    document.getElementById('api-key-input').addEventListener('change', function() {
        const apiKey = this.value.trim();
        if (apiKey) {
            sessionStorage.setItem('kiro_api_key', apiKey);
        }
    });
    
    // Show info message about API endpoint
    if (API_CONFIG.endpoint && API_CONFIG.endpoint !== 'API_ENDPOINT_PLACEHOLDER') {
        console.log('API Endpoint configured:', API_CONFIG.endpoint);
    } else {
        const warning = document.createElement('div');
        warning.className = 'result error';
        warning.style.display = 'block';
        warning.innerHTML = `
            <h3>⚠️ Configuration Required</h3>
            <p>API endpoint has not been configured. Please run the upload script to configure the frontend.</p>
        `;
        document.querySelector('.container').insertBefore(warning, document.querySelector('.api-config-card'));
    }
});
