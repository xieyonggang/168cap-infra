"""
FastAPI template for 168cap infrastructure
This template provides a basic FastAPI app structure with health checks
"""

import os
from datetime import datetime
from typing import Dict, Any
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

# Initialize FastAPI app
app = FastAPI(
    title=os.getenv("APP_NAME", "168cap LLM App"),
    description="LLM application running on 168cap infrastructure",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root() -> Dict[str, Any]:
    """Root endpoint"""
    return {
        "message": "Welcome to your 168cap LLM App!",
        "app_name": os.getenv("APP_NAME", "Unknown"),
        "timestamp": datetime.utcnow().isoformat(),
        "status": "running"
    }

@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """Health check endpoint for Docker and load balancers"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "app_name": os.getenv("APP_NAME", "Unknown"),
        "environment": os.getenv("ENVIRONMENT", "development")
    }

@app.get("/api/info")
async def app_info() -> Dict[str, Any]:
    """Application information endpoint"""
    return {
        "app_name": os.getenv("APP_NAME", "Unknown"),
        "version": "1.0.0",
        "environment": os.getenv("ENVIRONMENT", "development"),
        "debug": os.getenv("DEBUG", "false").lower() == "true",
        "timestamp": datetime.utcnow().isoformat()
    }

# Example LLM endpoint (customize based on your needs)
@app.post("/api/chat")
async def chat_endpoint(message: str) -> Dict[str, Any]:
    """
    Example chat endpoint - customize based on your LLM integration
    """
    try:
        # Add your LLM logic here
        # For example: response = await your_llm_client.generate(message)
        
        return {
            "response": f"Echo: {message}",  # Replace with actual LLM response
            "timestamp": datetime.utcnow().isoformat(),
            "model": os.getenv("MODEL_NAME", "unknown")
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Chat processing failed: {str(e)}")

@app.exception_handler(404)
async def not_found_handler(request, exc):
    """Custom 404 handler"""
    return JSONResponse(
        status_code=404,
        content={
            "error": "Endpoint not found",
            "timestamp": datetime.utcnow().isoformat(),
            "app_name": os.getenv("APP_NAME", "Unknown")
        }
    )

@app.exception_handler(500)
async def internal_error_handler(request, exc):
    """Custom 500 handler"""
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "timestamp": datetime.utcnow().isoformat(),
            "app_name": os.getenv("APP_NAME", "Unknown")
        }
    )

if __name__ == "__main__":
    # For development only
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=os.getenv("DEBUG", "false").lower() == "true"
    )