class DeviceFingerprint {
  static async generate() {
    console.log('🔍 Starting device fingerprint');
    const data = await this.collectDeviceData();
    window.deviceFingerprint = data;
    console.log('✨ Device data collected:', data);
    return data;
  }

  static async collectDeviceData() {
    const databaseInfo = await this.checkStorage();
    console.log('📦 Database info:', databaseInfo);

    const uiData = {
      browser: {
        userAgent: navigator.userAgent,
        language: navigator.language
      },
      hardware: {
        platform: navigator.platform,
        cpuCores: navigator.hardwareConcurrency || 'unknown',
        memory: navigator.deviceMemory || 'unknown',
        oscpu: navigator.oscpu || 'unknown',
        architecture: navigator.userAgentData?.architecture || 'unknown',
        model: 'unknown'
      },
      screen: {
        width: window.screen.width,
        height: window.screen.height,
        colorDepth: window.screen.colorDepth,
        pixelRatio: window.devicePixelRatio
      }
    };

    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
      if (gl) {
        const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
        if (debugInfo) {
          uiData.gpu = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
        }
      }
    } catch (e) {
      console.warn('GPU info collection failed:', e);
    }

    return {
      ...uiData,
      database: databaseInfo
    };
  }

  static async checkStorage() {
    try {
      console.log('🔍 Checking storage locations');
      let databasePath;
      let source;

      // 1. Check localStorage first
      const storedPath = localStorage.getItem('device_database_path');
      if (storedPath) {
        // Important: Decode the path only once
        databasePath = decodeURIComponent(storedPath);
        console.log('✅ Found database path in localStorage:', databasePath);
        source = 'localStorage';
      }

      // 2. Check cookies if no localStorage
      if (!databasePath) {
        const cookiePath = this.getCookie('device_database_path');
        if (cookiePath) {
          databasePath = decodeURIComponent(cookiePath);
          console.log('✅ Found database path in cookie:', databasePath);
          source = 'cookie';
        }
      }

      // If path found, sync across all storage methods
      if (databasePath) {
        await this.syncToStorage(databasePath);
        return {
          path: databasePath,
          exists: true,
          source
        };
      }

      return { exists: false };
    } catch (error) {
      console.error('🚨 Storage check error:', error);
      return { exists: false };
    }
  }

  static getCookie(name) {
    try {
      console.log('🔍 Looking for cookie:', name);
      const cookies = document.cookie.split(';');
      for (let cookie of cookies) {
        const [cookieName, cookieValue] = cookie.split('=').map(c => c.trim());
        if (cookieName === name) {
          console.log('✅ Found cookie:', cookieValue);
          return cookieValue;
        }
      }
      console.log('❌ Cookie not found:', name);
      return null;
    } catch (error) {
      console.error('🚨 Cookie read error:', error);
      return null;
    }
  }

  static async syncToStorage(path) {
    if (!path) {
      console.warn('❌ No path provided for storage sync');
      return;
    }
    
    try {
      console.log('🔄 Starting storage sync for path:', path);
      
      // Store the path without additional encoding
      const cleanPath = decodeURIComponent(path);
      
      // Set localStorage
      if (window.localStorage) {
        localStorage.setItem('device_database_path', cleanPath);
        localStorage.setItem('device_sync_time', new Date().toISOString());
        console.log('✅ localStorage updated');
      }

      // Set cookie with single encoding
      const cookieString = [
        `device_database_path=${encodeURIComponent(cleanPath)}`,
        'path=/',
        'domain=.superappproject.com',
        'secure',
        'samesite=lax',
        `max-age=${365 * 24 * 60 * 60}`
      ].join('; ');

      document.cookie = cookieString;
      console.log('🍪 Set cookie:', cookieString);

      const verification = await this.verifyStorage(cleanPath);
      console.log('📊 Storage verification results:', verification);
      
      if (!verification.success) {
        console.error('⚠️ Storage verification failed:', verification.errors);
      }
    } catch (error) {
      console.error('❌ Storage sync failed:', error);
      throw error;
    }
  }

  static async verifyStorage(path) {
    const verification = {
      success: true,
      errors: []
    };

    // Verify localStorage
    if (window.localStorage) {
      const storedPath = localStorage.getItem('device_database_path');
      if (decodeURIComponent(storedPath) !== decodeURIComponent(path)) {
        verification.success = false;
        verification.errors.push('localStorage mismatch');
      }
    }

    // Verify cookie
    const cookiePath = this.getCookie('device_database_path');
    if (cookiePath && decodeURIComponent(cookiePath) !== decodeURIComponent(path)) {
      verification.success = false;
      verification.errors.push('cookie mismatch');
    }

    return verification;
  }
}

export default DeviceFingerprint;
