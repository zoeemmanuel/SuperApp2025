import React from 'react';
import { createRoot } from 'react-dom/client';
import Dashboard from './components/Dashboard';
import UnifiedLogin from './components/auth/UnifiedLogin';
import DeviceFingerprint from './device_fingerprint';

// Make components available globally
window.React = React;
window.createRoot = createRoot;
window.Dashboard = Dashboard;

document.addEventListener('DOMContentLoaded', async () => {
  try {
    // Debug endpoint check
    try {
      const response = await fetch('/api/v1/debug/state');
      const debug = await response.json();
      console.log('🔍 Debug State:', debug);
    } catch (e) {
      console.warn('⚠️ Debug endpoint check failed:', e);
    }

    // Sync cookies to localStorage
    const dbPath = document.cookie.split(';')
      .find(c => c.trim().startsWith('device_database_path='));
      
    if (dbPath) {
      const value = dbPath.split('=')[1];
      console.log('📦 Syncing to localStorage:', value);
      localStorage.setItem('device_database_path', value);
    }

    // Initialize device fingerprinting for login page
    if (document.getElementById('login-root')) {
      try {
        const deviceData = await DeviceFingerprint.generate();
        console.log('🔍 Device data ready:', deviceData);
        window.deviceData = deviceData; // Store for component access
      } catch (error) {
        console.error('❌ Failed to generate device data:', error);
      }
    }

    // Check for dashboard mount point
    const dashboardRoot = document.getElementById('dashboard-root');
    const loginRoot = document.getElementById('login-root');

    if (dashboardRoot) {
      const userData = JSON.parse(dashboardRoot.getAttribute('data-user'));
      console.log('🚀 Initializing dashboard with data:', userData);
      
      const root = createRoot(dashboardRoot);
      root.render(
        React.createElement(
          React.StrictMode,
          null,
          React.createElement(Dashboard, { userData })
        )
      );
    } else if (loginRoot) {
      console.log('🔐 Initializing login page');
      const root = createRoot(loginRoot);
      root.render(
        React.createElement(
          React.StrictMode,
          null,
          React.createElement(UnifiedLogin)
        )
      );
    }
  } catch (error) {
    console.error('❌ Application initialization error:', error);
    const mountPoint = document.getElementById('dashboard-root') || document.getElementById('login-root');
    if (mountPoint) {
      mountPoint.innerHTML = `
        <div class="p-4 bg-red-50 text-red-600 rounded">
          Error initializing application: ${error.message}
        </div>
      `;
    }
  } finally {
    // Hide the loading spinner
    const loader = document.getElementById('app-loading');
    if (loader) loader.style.display = 'none';
  }
});

// Export for webpack
export { DeviceFingerprint };
