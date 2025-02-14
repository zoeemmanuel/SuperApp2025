import React, { useState, useEffect } from 'react';
import { Alert, AlertTitle } from '@/components/ui/alert';
import { X } from 'lucide-react';
import DeviceFingerprint from '../../device_fingerprint';

const UnifiedLogin = () => {
  // State management
  const [identifier, setIdentifier] = useState('');
  const [step, setStep] = useState('checking');
  const [verificationCode, setVerificationCode] = useState('');
  const [handle, setHandle] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [deviceInfo, setDeviceInfo] = useState(null);
  const [allowGuid, setAllowGuid] = useState(false);
  const [knownHandle, setKnownHandle] = useState('');
  const [maskedPhone, setMaskedPhone] = useState('');
  const [verifiedPhone, setVerifiedPhone] = useState('');
  const [databasePath, setDatabasePath] = useState(null);

  // API URL handling
  const getApiUrl = (endpoint) => {
    const domain = 'superappproject.com';
    return `https://${domain}${endpoint}`;
  };
// Device data management
  const getDeviceData = async (forceRefresh = false) => {
    try {
      let currentDeviceInfo = !forceRefresh && (deviceInfo || window.deviceInfo);
      
      if (!currentDeviceInfo) {
        console.log('Generating new device fingerprint...');
        currentDeviceInfo = await DeviceFingerprint.generate();
        setDeviceInfo(currentDeviceInfo);
        window.deviceInfo = currentDeviceInfo;
      }

      const dbPath = databasePath || localStorage.getItem('device_database_path');
      if (dbPath && (!currentDeviceInfo.database || currentDeviceInfo.database.path !== dbPath)) {
        console.log('Updating device info with stored database path:', dbPath);
        currentDeviceInfo = {
          ...currentDeviceInfo,
          database: {
            path: dbPath,
            exists: true
          }
        };
      }

      return currentDeviceInfo;
    } catch (error) {
      console.error('Error getting device data:', error);
      throw error;
    }
  };

  // Device initialization and checking
  useEffect(() => {
    let mounted = true;

    const initializeDevice = async () => {
      console.log('Starting device initialization...');
      try {
        const deviceData = await getDeviceData(true);
        if (!mounted) return;

        console.log('Device data initialized:', deviceData);
        await checkDevice(deviceData);
      } catch (error) {
        console.error('Device initialization failed:', error);
        if (!mounted) return;
        
        setError('Unable to initialize device. Please try again.');
        setStep('initial');
      }
    };

    initializeDevice();
    return () => {
      mounted = false;
    };
  }, []);

const checkDevice = async (info) => {
  if (!info) {
    console.error('Device info missing in checkDevice');
    setError('Device information unavailable');
    setStep('initial');
    return;
  }

  try {
    console.log('Checking device with info:', info);
    const response = await fetch(getApiUrl('/api/v1/auth/check_device'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      credentials: 'include',
      body: JSON.stringify({ device_data: info })
    });

    const data = await response.json();
    await DeviceFingerprint.handleStorageHeader(response);

    if (data.database_path) {
      localStorage.setItem('device_database_path', data.database_path);
      setDatabasePath(data.database_path);
    }

    // Auto-login if device is verified
    if (data.status === 'device_known' && data.verified) {
      window.location.href = data.redirect_to;
      return;
    }

    // Show welcome back if device is known but needs verification
    if (data.status === 'device_known') {
      setKnownHandle(data.handle);
      setMaskedPhone(data.masked_phone);
      setAllowGuid(true);
      setIdentifier(data.handle);
    }

    setStep('initial');
  } catch (error) {
    console.error('Device check error:', error);
    setError(error.message || 'Unable to verify device');
    setStep('initial');
  }
};

const handleInitialSubmit = async (e) => {
  e.preventDefault();
  setError('');
  setIsLoading(true);

  try {
    const trimmedIdentifier = identifier.trim();
    const isGuid = trimmedIdentifier.startsWith('@');
    
    // Validate input format
    if (isGuid && !trimmedIdentifier.match(/^@[a-zA-Z0-9_]+$/)) {
      throw new Error('Invalid handle format');
    }
    
    if (!isGuid && !trimmedIdentifier.match(/^\+?(?:44|65)\d{10}$/)) {
      throw new Error('Please enter a valid UK (+44) or Singapore (+65) phone number');
    }

    const deviceData = await getDeviceData();
    const response = await fetch(getApiUrl('/api/v1/auth/phone_login'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      credentials: 'include',
      body: JSON.stringify({
        device_data: deviceData,
        [isGuid ? 'handle' : 'phone']: trimmedIdentifier
      })
    });

    const data = await response.json();
    await DeviceFingerprint.handleStorageHeader(response);

    if (data.database_path) {
      localStorage.setItem('device_database_path', data.database_path);
      setDatabasePath(data.database_path);
    }

    switch (data.status) {
      case 'device_known':
        setKnownHandle(data.handle);
        setMaskedPhone(data.masked_phone);
        if (data.verified) {
          window.location.href = data.redirect_to;
        } else {
          setStep('code');
          setMessage(data.message || 'Please verify your device');
        }
        break;

      case 'pending_verification':
        setStep('code');
        setMessage(data.message || 'Enter the verification code');
        if (!isGuid) setVerifiedPhone(trimmedIdentifier);
        break;

      case 'authenticated':
        window.location.href = data.redirect_to;
        break;

      default:
        throw new Error('Unexpected response');
    }
  } catch (error) {
    console.error('Authentication error:', error);
    setError(error.message || 'Authentication failed');
  } finally {
    setIsLoading(false);
  }
};

  const handleVerifyCode = async (e) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);

    try {
      const deviceData = await getDeviceData();
      const payload = {
        device_data: deviceData,
        code: verificationCode.toUpperCase(),
        identifier: identifier
      };

      const response = await fetch(getApiUrl('/api/v1/auth/verify_code'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        credentials: 'include',
        body: JSON.stringify(payload)
      });

      const data = await response.json();
      await DeviceFingerprint.handleStorageHeader(response);
      
      if (!response.ok) {
        throw new Error(data.message || 'Verification failed');
      }

      if (data.database_path) {
        localStorage.setItem('device_database_path', data.database_path);
        setDatabasePath(data.database_path);
      }

      switch (data.status) {
        case 'needs_handle':
          setStep('handle');
          setMessage('Choose a handle to continue');
          break;
        case 'authenticated':
          window.location.href = data.redirect_to;
          break;
        default:
          throw new Error('Unexpected response');
      }
    } catch (error) {
      console.error('Code verification error:', error);
      setError(error.message || 'Verification failed');
    } finally {
      setIsLoading(false);
    }
  };
// Render methods
  const renderCheckingStep = () => (
    <div className="text-center">
      <h2 className="text-2xl font-bold mb-6">Welcome to SuperApp</h2>
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-purple-600 mx-auto"></div>
      <p className="mt-4 text-gray-600">Checking your device...</p>
    </div>
  );

  const renderInitialStep = () => (
    <div>
      <h2 className="text-2xl font-bold mb-6 text-center">
        {knownHandle ? `Welcome back ${knownHandle}!` : 'Welcome to SuperApp'}
      </h2>
      
      <form onSubmit={handleInitialSubmit}>
        <div className="space-y-6">
          <div>
            <label htmlFor="identifier" className="block text-sm font-medium text-gray-700">
              {allowGuid ? 'Phone Number or Handle' : 'Phone Number'}
            </label>
            <div className="mt-1">
              <input
                id="identifier"
                name="identifier"
                type="text"
                required
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
                className="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm"
                placeholder={allowGuid ? '+44/+65 or @handle' : '+44/+65'}
                autoComplete="off"
                disabled={isLoading}
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={isLoading || !identifier.trim()}
            className={`w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white ${
              isLoading || !identifier.trim() 
                ? 'bg-purple-400 cursor-not-allowed'
                : 'bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500'
            }`}
          >
            {isLoading ? (
              <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
            ) : (
              'Continue'
            )}
          </button>
        </div>
      </form>
    </div>
  );

  const renderCodeStep = () => (
    <div>
      <h2 className="text-2xl font-bold mb-2 text-center">Enter Verification Code</h2>
      <p className="text-center text-gray-600 mb-6">{message}</p>
      
      <form onSubmit={handleVerifyCode}>
        <div className="space-y-6">
          <div>
            <label htmlFor="code" className="block text-sm font-medium text-gray-700">
              Verification Code
            </label>
            <div className="mt-1">
              <input
                id="code"
                name="code"
                type="text"
                required
                value={verificationCode}
                onChange={(e) => setVerificationCode(e.target.value.toUpperCase())}
                className="appearance-none block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm"
                placeholder="Enter code"
                autoComplete="off"
                disabled={isLoading}
                maxLength={6}
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={isLoading || verificationCode.length !== 6}
            className={`w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white ${
              isLoading || verificationCode.length !== 6
                ? 'bg-purple-400 cursor-not-allowed'
                : 'bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500'
            }`}
          >
            {isLoading ? (
              <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
            ) : (
              'Verify'
            )}
          </button>
        </div>
      </form>
    </div>
  );

const renderHandleStep = () => (
  <div>
    <h2 className="text-2xl font-bold mb-2 text-center">Choose Your Handle</h2>
    <p className="text-center text-gray-600 mb-6">This will be your unique identifier</p>
    
    <form onSubmit={handleHandleSubmit}>
      <div className="space-y-6">
        <div>
          <label htmlFor="handle" className="block text-sm font-medium text-gray-700">
            Handle
          </label>
<div className="mt-1 relative">
  <span className="absolute inset-y-0 left-0 pl-3 flex items-center text-gray-500">
    @
  </span>
  <input
    id="handle"
    name="handle"
    type="text"
    required
    value={handle}
    onChange={(e) => setHandle(e.target.value)}
    className="appearance-none block w-full pl-8 pr-3 py-2 border border-gray-300 rounded-md shadow-sm placeholder-gray-400 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm"
    placeholder="username"
    autoComplete="off"
    disabled={isLoading}
  />
</div>
        </div>

        <button
          type="submit"
          disabled={isLoading || !handle.trim()}
          className={`w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white ${
            isLoading || !handle.trim() 
              ? 'bg-purple-400 cursor-not-allowed'
              : 'bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500'
          }`}
        >
          {isLoading ? (
            <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-white"></div>
          ) : (
            'Continue'
          )}
        </button>
      </div>
    </form>
  </div>
);

const handleHandleSubmit = async (e) => {
  e.preventDefault();
  setError('');
  setIsLoading(true);

  try {
    const deviceData = await getDeviceData();
    const response = await fetch(getApiUrl('/api/v1/auth/update_handle'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      credentials: 'include',
      body: JSON.stringify({
        handle: handle.startsWith('@') ? handle : `@${handle}`,
        device_data: deviceData
      })
    });

    const data = await response.json();
    console.log('Response:', data);

    // Set storage before redirect
    if (data.database_path) {
      localStorage.setItem('device_database_path', data.database_path);
      setDatabasePath(data.database_path);
    }

    // Immediate redirect without status check
    if (data.redirect_to) {
      document.location.href = data.redirect_to;
      return;
    }

  } catch (error) {
    if (!error.message.includes('navigation')) {
      console.error('Handle update error:', error);
      setError('Failed to update handle');
    }
  } finally {
    setIsLoading(false);
  }
};

const renderStep = () => {
  switch (step) {
    case 'checking':
      return renderCheckingStep();
    case 'initial':
      return renderInitialStep();
    case 'code':
      return renderCodeStep();
    case 'handle':
      return renderHandleStep();
    default:
      return null;
  }
};

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
          {renderStep()}
          {error && (
            <div className="mt-4">
              <Alert variant="destructive">
                <AlertTitle className="flex items-center justify-between">
                  <span>Error</span>
                  <X 
                    className="h-4 w-4 cursor-pointer" 
                    onClick={() => setError('')}
                  />
                </AlertTitle>
                <p className="text-sm">{error}</p>
              </Alert>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default UnifiedLogin;
