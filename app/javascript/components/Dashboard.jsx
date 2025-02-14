import React, { useState, useEffect } from 'react';
import {
  Cog as CogIcon,
  LogOut as LogoutIcon,
  Smartphone as DeviceMobileIcon,
  Monitor as DesktopComputerIcon,
  XCircle as XCircleIcon,
  ShieldCheck as ShieldCheckIcon,
  Info as InformationCircleIcon,
} from 'lucide-react';

const Dashboard = ({ userData }) => {
  const [userInfo, setUserInfo] = useState(userData);
  const [error, setError] = useState(null);
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [isResetModalOpen, setIsResetModalOpen] = useState(false);
  const [isDetailsModalOpen, setIsDetailsModalOpen] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState(null);
  const [newHandle, setNewHandle] = useState(userData?.handle?.replace(/^@/, '') || '');
  const [isResetting, setIsResetting] = useState(false);

  // Group devices by database path
  const groupedDevices = React.useMemo(() => {
    if (!userInfo?.devices) return [];
    
    const deviceMap = new Map();
    userInfo.devices.forEach(device => {
      const dbPath = device.device_info?.database_path;
      if (!deviceMap.has(dbPath)) {
        deviceMap.set(dbPath, {
          ...device,
          browser_sessions: 1
        });
      } else {
        const existing = deviceMap.get(dbPath);
        // Keep the most recent activity date
        if (new Date(device.last_active_at) > new Date(existing.last_active_at)) {
          existing.last_active_at = device.last_active_at;
        }
        existing.browser_sessions += 1;
      }
    });
    return Array.from(deviceMap.values());
  }, [userInfo?.devices]);

const handleLogout = async () => {
  try {
    const response = await fetch('/api/v1/auth/logout', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      credentials: 'include'
    });
    
    const data = await response.json();
    
    if (response.ok) {
      // Clear any sensitive session data
      sessionStorage.clear();
      
      // Preserve only necessary device info
      const devicePath = localStorage.getItem('device_database_path');
      localStorage.clear();
      if (devicePath) {
        localStorage.setItem('device_database_path', devicePath);
      }
      
      // Force a clean redirect to login
      window.location.replace(data.redirect_to || '/login');
    } else {
      setError('Failed to logout');
    }
  } catch (err) {
    console.error('Logout error:', err);
    setError('Failed to logout');
  }
};
  const getDeviceIcon = (deviceType) => {
    return deviceType === 'mobile' ? 
      <DeviceMobileIcon className="w-6 h-6 text-gray-600" /> : 
      <DesktopComputerIcon className="w-6 h-6 text-gray-600" />;
  };

  const formatLastActive = (date) => {
    const now = new Date();
    const lastActive = new Date(date);
    const diffHours = Math.floor((now - lastActive) / (1000 * 60 * 60));
    
    if (diffHours < 1) return 'Just now';
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffHours < 48) return 'Yesterday';
    return lastActive.toLocaleDateString();
  };

  const handleUpdateHandle = async () => {
    try {
      const formattedHandle = newHandle.replace(/^@+/, '');
      const response = await fetch('/api/v1/auth/update_handle', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        credentials: 'include',
        body: JSON.stringify({ handle: formattedHandle })
      });
      
      const data = await response.json();
      
      if (response.ok && data.status === 'success') {
        setUserInfo(prev => ({ ...prev, handle: data.handle }));
        setIsEditModalOpen(false);
      } else {
        setError(data.message || 'Failed to update handle');
      }
    } catch (err) {
      setError('Failed to update handle');
    }
  };

  const handleResetDevices = async () => {
    setIsResetting(true);
    setError(null);
    
    try {
      const response = await fetch('/api/v1/devices/reset', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        },
        credentials: 'include'
      });
      
      const data = await response.json();
      
      if (response.ok && data.status === 'success') {
        if (data.clear_storage) {
          localStorage.clear();
          sessionStorage.clear();
        }

        setError({
          type: 'success',
          message: 'Devices reset successfully. Redirecting to login...'
        });

        setTimeout(() => {
          window.location.href = data.redirect_to || '/login';
        }, 1500);
      } else {
        setError(data.message || 'Failed to reset devices');
        setIsResetModalOpen(false);
      }
    } catch (err) {
      setError('Failed to reset devices');
      setIsResetModalOpen(false);
    } finally {
      setIsResetting(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      {/* Header */}
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-2xl font-bold text-gray-900">SuperApp</h1>
        <div className="flex items-center gap-4">
          <button
            onClick={() => setIsResetModalOpen(true)}
            className="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 hover:text-gray-900"
          >
            <ShieldCheckIcon className="w-5 h-5 mr-2" />
            Reset Devices
          </button>
          <button
            onClick={handleLogout}
            className="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 hover:text-gray-900"
          >
            <LogoutIcon className="w-5 h-5 mr-2" />
            Logout
          </button>
        </div>
      </div>

      {/* User Info */}
      <div className="bg-white rounded-lg shadow-sm border p-6 mb-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-xl font-semibold text-gray-900">
              {userInfo?.handle || ''}
            </h2>
            <p className="text-sm text-gray-500">{userInfo?.phone || ''}</p>
          </div>
          <button
            onClick={() => setIsEditModalOpen(true)}
            className="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-700 hover:text-gray-900"
          >
            <CogIcon className="w-5 h-5 mr-2" />
            Edit Handle
          </button>
        </div>
      </div>

      {/* Devices */}
      <div className="bg-white rounded-lg shadow-sm border">
        <div className="p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Your Devices</h3>
          <div className="space-y-4">
            {groupedDevices.map((device) => (
              <div 
                key={device.id}
                className={`flex items-center justify-between p-4 rounded-lg border ${
                  device.is_current ? 'bg-blue-50 border-blue-200' : 'border-gray-200'
                }`}
              >
                <div className="flex items-center gap-4">
                  {getDeviceIcon(device.device_type)}
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-gray-900">
                        {device.device_type === 'mobile' ? 'Mobile Device' : 'Desktop'}
                        {device.is_current && (
                          <span className="ml-2 inline-flex items-center px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-800 rounded-full">
                            Current Device
                          </span>
                        )}
                      </p>
                    </div>
                    <p className="text-sm text-gray-500">
                      Last active: {formatLastActive(device.last_active_at)}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => {
                    setSelectedDevice(device);
                    setIsDetailsModalOpen(true);
                  }}
                  className="p-2 text-gray-400 hover:text-gray-600 rounded-full hover:bg-gray-100"
                >
                  <InformationCircleIcon className="w-5 h-5" />
                </button>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Error Display */}
      {error && (
        <div className={`mt-4 p-4 rounded-md flex items-center ${
          error.type === 'success' ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'
        }`}>
          <XCircleIcon className="w-5 h-5 mr-2" />
          {error.message || error}
        </div>
      )}

      {/* Edit Handle Modal */}
      {isEditModalOpen && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Edit Handle</h3>
            <div className="relative">
              <span className="absolute inset-y-0 left-0 pl-3 flex items-center text-gray-500">@</span>
              <input
                type="text"
                value={newHandle}
                onChange={(e) => setNewHandle(e.target.value.replace(/^@+/, ''))}
                className="pl-8 w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="handle"
              />
            </div>
            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={() => setIsEditModalOpen(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 hover:text-gray-500"
              >
                Cancel
              </button>
              <button
                onClick={handleUpdateHandle}
                className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reset Devices Modal */}
      {isResetModalOpen && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Reset All Devices</h3>
            <p className="text-sm text-gray-500">
              This will reset all your devices. You will need to re-verify all devices to access your account again.
            </p>
            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={() => setIsResetModalOpen(false)}
                disabled={isResetting}
                className="px-4 py-2 text-sm font-medium text-gray-700 hover:text-gray-500 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                onClick={handleResetDevices}
                disabled={isResetting}
                className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700 disabled:opacity-50 flex items-center"
              >
                {isResetting ? (
                  <>
                    <span className="animate-spin mr-2">⟳</span>
                    Resetting...
                  </>
                ) : (
                  'Reset Devices'
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Device Details Modal */}
      {isDetailsModalOpen && selectedDevice && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Device Details</h3>
            <div className="space-y-3">
              <p><span className="font-medium">Type:</span> {selectedDevice.device_type === 'mobile' ? 'Mobile Device' : 'Desktop'}</p>
              <p><span className="font-medium">Active Sessions:</span> {selectedDevice.browser_sessions}</p>
              <p><span className="font-medium">Last Active:</span> {new Date(selectedDevice.last_active_at).toLocaleString()}</p>
              {selectedDevice.device_info?.platform && (
                <p><span className="font-medium">Platform:</span> {selectedDevice.device_info.platform}</p>
              )}
            </div>
            <div className="mt-6 flex justify-end">
              <button
                onClick={() => setIsDetailsModalOpen(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 hover:text-gray-500"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Dashboard;
